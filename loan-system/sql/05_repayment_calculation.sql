-- ============================================================
-- SYSTEM-CALCULATED REPAYMENT (reducing balance / PMT method)
-- Run this AFTER 01, 02, 03, 04.
-- ============================================================

-- ---------- 1. Per-community loan settings (so rate/fee/cap are tunable, not hardcoded) ----------
create table loan_settings (
  community_id uuid primary key references communities(id),
  annual_interest_rate numeric(6,3) not null default 10.0,     -- e.g. 10 = 10% p.a.
  processing_fee_rate numeric(6,4) not null default 0.005,     -- 0.5%
  max_debt_to_income_ratio numeric(5,4) not null default 0.20, -- 20%
  updated_at timestamptz not null default now()
);

-- ---------- 2. New loan fields needed for the calculation ----------
alter table loans add column net_pay numeric(14,2);              -- monthly net salary, entered on the form
alter table loans add column term_months int;                     -- "Period (Months)" from your sheet
alter table loans add column application_date date not null default current_date;
alter table loans add column expected_end_date date;              -- the date field the period is derived from
alter table loans add column interest_rate numeric(6,3);           -- snapshot of the rate used, for history
alter table loans add column processing_fee numeric(14,2);
alter table loans add column debt_to_income_ratio numeric(6,4);    -- installment / net_pay

-- (installment_amount, outstanding_balance, next_deduction_date already exist from 04_repayments.sql)

-- ---------- 3. PMT-equivalent function ----------
-- Mirrors: =-PMT((rate/100)/12, nper, principal, 0, 0)
create or replace function calc_pmt(p_principal numeric, p_annual_rate_pct numeric, p_nper int)
returns numeric language plpgsql immutable as $$
declare
  v_rate numeric;
begin
  if p_nper is null or p_nper <= 0 or p_principal is null then
    return null;
  end if;
  v_rate := (p_annual_rate_pct / 100) / 12;
  if v_rate = 0 then
    return round(p_principal / p_nper, 2);
  end if;
  return round(p_principal * v_rate / (1 - power(1 + v_rate, -p_nper)), 2);
end;
$$;

-- ---------- 4. Auto-calculate term, rate, fee, installment, and DTI ratio ----------
create or replace function calc_loan_financials()
returns trigger language plpgsql security definer as $$
declare
  v_settings loan_settings%rowtype;
begin
  select * into v_settings from loan_settings where community_id = new.community_id;
  if not found then
    v_settings.annual_interest_rate := 10.0;
    v_settings.processing_fee_rate := 0.005;
    v_settings.max_debt_to_income_ratio := 0.20;
  end if;

  -- derive term in months from the end date, if not set directly
  if new.expected_end_date is not null then
    new.term_months := greatest(1,
      (extract(year from age(new.expected_end_date, new.application_date)) * 12
       + extract(month from age(new.expected_end_date, new.application_date)))::int
    );
  end if;

  new.interest_rate := v_settings.annual_interest_rate;
  new.processing_fee := round(new.amount_requested * v_settings.processing_fee_rate, 2);
  new.installment_amount := calc_pmt(new.amount_requested, new.interest_rate, new.term_months);

  if new.net_pay is not null and new.net_pay > 0 and new.installment_amount is not null then
    new.debt_to_income_ratio := round(new.installment_amount / new.net_pay, 4);
  else
    new.debt_to_income_ratio := null;
  end if;

  return new;
end;
$$;

create trigger a_calc_loan_financials
  before insert or update of amount_requested, term_months, net_pay, expected_end_date on loans
  for each row execute function calc_loan_financials();
-- Named with an "a_" prefix so it fires before the "b_" submission trigger below
-- (Postgres runs same-timing triggers in name order).

-- ---------- 5. Re-point the submission trigger to enforce the 20% cap ----------
drop trigger if exists on_loan_submission on loans;

create or replace function handle_loan_submission()
returns trigger language plpgsql security definer as $$
declare
  v_stage workflow_stages%rowtype;
  v_max_ratio numeric;
begin
  if new.status = 'in_review' and old.status in ('draft','returned_to_applicant') then

    select max_debt_to_income_ratio into v_max_ratio
      from loan_settings where community_id = new.community_id;
    if v_max_ratio is null then v_max_ratio := 0.20; end if;

    if new.net_pay is null or new.term_months is null then
      raise exception 'Net pay and loan period must be provided before submitting.';
    end if;

    if new.debt_to_income_ratio > v_max_ratio then
      raise exception
        'Repayment of % is %.1f%% of net pay % — this exceeds the maximum allowed %.0f%%.',
        new.installment_amount, new.debt_to_income_ratio * 100, new.net_pay, v_max_ratio * 100;
    end if;

    new.current_stage_order := 1;
    new.submitted_at := now();

    select * into v_stage from workflow_stages
      where template_id = new.template_id and stage_order = 1;

    perform notify_role_holders(
      new.community_id, v_stage.role_id, new.id,
      'New loan application',
      'A loan application from ' || (select full_name from profiles where id = new.applicant_id)
        || ' is waiting at your stage (' || v_stage.stage_name || ').'
    );
  end if;
  return new;
end;
$$;

create trigger b_loan_submission
  before update on loans
  for each row execute function handle_loan_submission();

-- ---------- 6. Amortization schedule (mirrors your spreadsheet: Installment/Interest/Principal/Balance) ----------
create table loan_amortization_schedule (
  id uuid primary key default uuid_generate_v4(),
  loan_id uuid not null references loans(id) on delete cascade,
  period_number int not null,
  due_date date not null,
  installment numeric(14,2) not null,
  interest numeric(14,2) not null,
  principal numeric(14,2) not null,
  balance numeric(14,2) not null,
  unique (loan_id, period_number)
);

alter table loan_amortization_schedule enable row level security;

create policy "amortization: applicant can view own"
  on loan_amortization_schedule for select
  using (exists (select 1 from loans l where l.id = loan_amortization_schedule.loan_id and l.applicant_id = auth.uid()));

create policy "amortization: treasurer/auditor/chair can view community"
  on loan_amortization_schedule for select
  using (exists (
    select 1 from loans l
    where l.id = loan_amortization_schedule.loan_id
      and (has_role('treasurer', l.community_id) or has_role('auditor', l.community_id)
           or has_role('community_chairperson', l.community_id))
  ));

create or replace function generate_amortization_schedule(p_loan_id uuid)
returns void language plpgsql security definer as $$
declare
  v_loan loans%rowtype;
  v_monthly_rate numeric;
  v_balance numeric;
  v_interest numeric;
  v_principal numeric;
  i int;
begin
  select * into v_loan from loans where id = p_loan_id;
  v_monthly_rate := (v_loan.interest_rate / 100) / 12;
  v_balance := v_loan.amount_disbursed;

  delete from loan_amortization_schedule where loan_id = p_loan_id;

  for i in 1..v_loan.term_months loop
    v_interest := round(v_balance * v_monthly_rate, 2);
    v_principal := round(v_loan.installment_amount - v_interest, 2);
    v_balance := round(v_balance - v_principal, 2);
    if i = v_loan.term_months then v_balance := 0; end if;

    insert into loan_amortization_schedule (loan_id, period_number, due_date, installment, interest, principal, balance)
    values (p_loan_id, i, (v_loan.next_deduction_date + ((i - 1) || ' months')::interval)::date,
            v_loan.installment_amount, v_interest, v_principal, v_balance);
  end loop;
end;
$$;

-- ---------- 7. Disbursement no longer needs a manually-entered installment amount ----------
-- (it's already computed by calc_loan_financials at application time)
-- Only first_deduction_date is required from the Treasurer at disbursement.
create or replace function process_stage_action()
returns trigger language plpgsql security definer as $$
declare
  v_loan loans%rowtype;
  v_max_stage int;
  v_current_stage workflow_stages%rowtype;
  v_target_stage workflow_stages%rowtype;
  v_applicant_name text;
begin
  select * into v_loan from loans where id = new.loan_id;
  select full_name into v_applicant_name from profiles where id = v_loan.applicant_id;

  select * into v_current_stage from workflow_stages
    where template_id = v_loan.template_id and stage_order = v_loan.current_stage_order;

  if new.action = 'rejected' then

    if v_loan.current_stage_order = 1 then
      update loans set status = 'returned_to_applicant' where id = new.loan_id;
      perform notify_applicant(
        new.loan_id, 'Loan sent back to you',
        v_current_stage.stage_name || ' returned your application: ' || new.comment
      );
    else
      update loans set current_stage_order = current_stage_order - 1, status = 'in_review'
        where id = new.loan_id;

      select * into v_target_stage from workflow_stages
        where template_id = v_loan.template_id and stage_order = v_loan.current_stage_order - 1;

      perform notify_role_holders(
        v_loan.community_id, v_target_stage.role_id, new.loan_id,
        'Loan sent back to your stage',
        v_current_stage.stage_name || ' sent ' || v_applicant_name || '''s loan back to you: ' || new.comment
      );
      perform notify_applicant(
        new.loan_id, 'Your loan was sent back a step',
        v_current_stage.stage_name || ' sent your loan back to ' || v_target_stage.stage_name || ': ' || new.comment
      );
    end if;

  elsif new.action = 'approved' then
    select max(stage_order) into v_max_stage from workflow_stages where template_id = v_loan.template_id;

    if v_loan.current_stage_order >= v_max_stage then
      if new.first_deduction_date is null then
        raise exception 'first_deduction_date is required to disburse a loan';
      end if;

      update loans
        set status = 'disbursed', disbursed_at = now(),
            amount_disbursed = coalesce(amount_disbursed, amount_requested),
            next_deduction_date = new.first_deduction_date,
            outstanding_balance = coalesce(amount_disbursed, amount_requested)
        where id = new.loan_id;

      perform generate_amortization_schedule(new.loan_id);

      perform notify_applicant(new.loan_id, 'Loan disbursed',
        'Your loan of ' || v_loan.amount_requested || ' has been disbursed. First deduction on '
          || new.first_deduction_date || '.');
      perform notify_all_past_actors(new.loan_id, 'Loan disbursed',
        v_applicant_name || '''s loan has been fully approved and disbursed.');
    else
      update loans set current_stage_order = current_stage_order + 1, status = 'in_review'
        where id = new.loan_id;

      select * into v_target_stage from workflow_stages
        where template_id = v_loan.template_id and stage_order = v_loan.current_stage_order + 1;

      perform notify_role_holders(
        v_loan.community_id, v_target_stage.role_id, new.loan_id,
        'Loan awaiting your approval',
        v_applicant_name || '''s loan is now at your stage (' || v_target_stage.stage_name || ').'
      );
      perform notify_applicant(new.loan_id, 'Your loan moved forward',
        'Your loan passed ' || v_current_stage.stage_name || ' and is now at ' || v_target_stage.stage_name || '.');
    end if;
  end if;

  return new;
end;
$$;

-- ---------- 8. Seed your community's settings row (edit the rate if it's not 10%) ----------
-- Run this once, replacing the UUID with your real community id from the `communities` table:
-- insert into loan_settings (community_id, annual_interest_rate, processing_fee_rate, max_debt_to_income_ratio)
-- values ('YOUR-COMMUNITY-UUID', 10.0, 0.005, 0.20);

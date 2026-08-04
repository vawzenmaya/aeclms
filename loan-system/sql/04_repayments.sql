-- ============================================================
-- REPAYMENT TRACKING (automatic, no real money movement)
-- Run this AFTER 01, 02, 03.
-- ============================================================

-- ---------- 1. Loans: repayment fields ----------
alter table loans drop constraint loans_status_check;
alter table loans add constraint loans_status_check
  check (status in ('draft','in_review','returned_to_applicant','rejected','approved',
                     'disbursed','completed'));

alter table loans add column installment_amount numeric(14,2);
alter table loans add column next_deduction_date date;
alter table loans add column outstanding_balance numeric(14,2);
alter table loans add column completed_at timestamptz;

-- ---------- 2. Disbursement action now carries installment details ----------
alter table loan_stage_actions add column installment_amount numeric(14,2);
alter table loan_stage_actions add column first_deduction_date date;

-- ---------- 3. Repayments log (the audit trail of each auto-deduction) ----------
create table repayments (
  id uuid primary key default uuid_generate_v4(),
  loan_id uuid not null references loans(id) on delete cascade,
  due_date date not null,
  amount numeric(14,2) not null,
  balance_after numeric(14,2) not null,
  created_at timestamptz not null default now()
);

alter table repayments enable row level security;

create policy "repayments: applicant can view own"
  on repayments for select
  using (exists (select 1 from loans l where l.id = repayments.loan_id and l.applicant_id = auth.uid()));

create policy "repayments: treasurer/auditor can view community"
  on repayments for select
  using (exists (
    select 1 from loans l
    where l.id = repayments.loan_id
      and (has_role('treasurer', l.community_id) or has_role('auditor', l.community_id)
           or has_role('community_chairperson', l.community_id))
  ));

-- ---------- 4. Update the disbursement branch of process_stage_action ----------
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
      -- Disbursement stage: installment details are required
      if new.installment_amount is null or new.first_deduction_date is null then
        raise exception 'installment_amount and first_deduction_date are required to disburse a loan';
      end if;

      update loans
        set status = 'disbursed', disbursed_at = now(),
            amount_disbursed = coalesce(amount_disbursed, amount_requested),
            installment_amount = new.installment_amount,
            next_deduction_date = new.first_deduction_date,
            outstanding_balance = coalesce(amount_disbursed, amount_requested)
        where id = new.loan_id;

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

-- ---------- 5. Daily job: auto-deduct due installments ----------
create or replace function run_daily_repayment_deductions()
returns void language plpgsql security definer as $$
declare
  r record;
  v_deduction numeric(14,2);
  v_new_balance numeric(14,2);
begin
  for r in
    select * from loans
    where status = 'disbursed'
      and next_deduction_date is not null
      and next_deduction_date <= current_date
      and outstanding_balance > 0
  loop
    v_deduction := least(r.installment_amount, r.outstanding_balance);
    v_new_balance := r.outstanding_balance - v_deduction;

    insert into repayments (loan_id, due_date, amount, balance_after)
    values (r.id, r.next_deduction_date, v_deduction, v_new_balance);

    if v_new_balance <= 0 then
      update loans set outstanding_balance = 0, status = 'completed', completed_at = now()
        where id = r.id;
      perform notify_applicant(r.id, 'Loan fully repaid',
        'Your loan has been fully repaid. Thank you!');
    else
      update loans
        set outstanding_balance = v_new_balance,
            next_deduction_date = (r.next_deduction_date + interval '1 month')::date
        where id = r.id;
      perform notify_applicant(r.id, 'Installment deducted',
        v_deduction || ' was deducted. Outstanding balance: ' || v_new_balance || '.');
    end if;
  end loop;
end;
$$;

-- ---------- 6. Schedule it with pg_cron (runs once a day at 01:00 UTC) ----------
-- Enable the extension first (Database -> Extensions -> pg_cron in the dashboard,
-- or run the line below):
create extension if not exists pg_cron;

select cron.schedule(
  'daily-loan-repayments',
  '0 1 * * *',
  $$select run_daily_repayment_deductions();$$
);

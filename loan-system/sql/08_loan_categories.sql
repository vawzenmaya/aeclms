-- ============================================================
-- LOAN CATEGORIES: Emergency (flat interest) vs Normal (reducing balance)
-- Run this AFTER 01 through 07 (i.e. after 00_full_schema.sql).
-- ============================================================

-- ---------- 1. New category field ----------
alter table loans add column loan_category text not null default 'normal'
  check (loan_category in ('emergency','normal'));

-- Top-ups only make sense for Normal loans, per your rule
alter table loans add constraint topup_only_for_normal
  check (loan_type <> 'topup' or loan_category = 'normal');

-- ---------- 2. Per-community tunable settings for both categories ----------
alter table loan_settings add column emergency_flat_interest_rate numeric(6,3) not null default 4.0;   -- 4%, one-time, not annualized
alter table loan_settings add column emergency_max_term_months int not null default 2;
alter table loan_settings add column normal_max_term_months int not null default 60; -- 5 years

-- ---------- 3. Flat-interest calculation (for Emergency loans) ----------
create or replace function calc_flat_installment(p_principal numeric, p_flat_rate_pct numeric, p_nper int)
returns numeric language plpgsql immutable as $$
begin
  if p_nper is null or p_nper <= 0 or p_principal is null then
    return null;
  end if;
  -- total repayable = principal + one-time flat interest, spread evenly
  return round((p_principal + p_principal * (p_flat_rate_pct / 100)) / p_nper, 2);
end;
$$;

-- ---------- 4. Recompute financials, branching by category, and enforce term limits ----------
create or replace function calc_loan_financials()
returns trigger language plpgsql security definer as $$
declare
  v_settings loan_settings%rowtype;
  v_max_term int;
begin
  select * into v_settings from loan_settings where community_id = new.community_id;
  if not found then
    v_settings.annual_interest_rate := 10.0;
    v_settings.processing_fee_rate := 0.005;
    v_settings.max_debt_to_income_ratio := 0.20;
    v_settings.emergency_flat_interest_rate := 4.0;
    v_settings.emergency_max_term_months := 2;
    v_settings.normal_max_term_months := 60;
  end if;

  if new.expected_end_date is not null then
    new.term_months := greatest(1,
      (extract(year from age(new.expected_end_date, new.application_date)) * 12
       + extract(month from age(new.expected_end_date, new.application_date)))::int
    );
  end if;

  -- Enforce the term limit for whichever category this loan is
  v_max_term := case when new.loan_category = 'emergency'
                     then v_settings.emergency_max_term_months
                     else v_settings.normal_max_term_months end;

  if new.term_months is not null and new.term_months > v_max_term then
    raise exception '% loans are limited to % months — you entered %.',
      initcap(new.loan_category), v_max_term, new.term_months;
  end if;

  new.processing_fee := round(new.amount_requested * v_settings.processing_fee_rate, 2);

  if new.loan_category = 'emergency' then
    new.interest_rate := v_settings.emergency_flat_interest_rate;
    new.interest_method := 'flat';
    new.installment_amount := calc_flat_installment(new.amount_requested, new.interest_rate, new.term_months);
  else
    new.interest_rate := v_settings.annual_interest_rate;
    new.interest_method := 'reducing_balance';
    new.installment_amount := calc_pmt(new.amount_requested, new.interest_rate, new.term_months);
  end if;

  if new.net_pay is not null and new.net_pay > 0 and new.installment_amount is not null then
    new.debt_to_income_ratio := round(new.installment_amount / new.net_pay, 4);
    new.dti_exceeded := new.debt_to_income_ratio > v_settings.max_debt_to_income_ratio;
  else
    new.debt_to_income_ratio := null;
    new.dti_exceeded := false;
  end if;

  if new.category = 'member' and new.employee_number is null then
    select employee_number into new.employee_number from profiles where id = new.applicant_id;
  end if;

  return new;
end;
$$;

-- make sure the trigger also fires when loan_category changes
drop trigger if exists a_calc_loan_financials on loans;
create trigger a_calc_loan_financials
  before insert or update of amount_requested, term_months, net_pay, expected_end_date, loan_category on loans
  for each row execute function calc_loan_financials();

-- ---------- 5. Amortization schedule: branch by category ----------
create or replace function generate_amortization_schedule(p_loan_id uuid)
returns void language plpgsql security definer as $$
declare
  v_loan loans%rowtype;
  v_monthly_rate numeric;
  v_balance numeric;
  v_interest numeric;
  v_principal numeric;
  v_flat_interest_per_period numeric;
  i int;
begin
  select * into v_loan from loans where id = p_loan_id;
  v_balance := v_loan.amount_disbursed;

  delete from loan_amortization_schedule where loan_id = p_loan_id;

  if v_loan.loan_category = 'emergency' then
    -- flat interest spread evenly: same interest portion every period
    v_flat_interest_per_period := round((v_loan.amount_disbursed * (v_loan.interest_rate / 100)) / v_loan.term_months, 2);

    for i in 1..v_loan.term_months loop
      v_principal := round(v_loan.installment_amount - v_flat_interest_per_period, 2);
      v_balance := round(v_balance - v_principal, 2);
      if i = v_loan.term_months then v_balance := 0; end if;

      insert into loan_amortization_schedule (loan_id, period_number, due_date, installment, interest, principal, balance)
      values (p_loan_id, i, (v_loan.next_deduction_date + ((i - 1) || ' months')::interval)::date,
              v_loan.installment_amount, v_flat_interest_per_period, v_principal, v_balance);
    end loop;
  else
    -- reducing balance, as before
    v_monthly_rate := (v_loan.interest_rate / 100) / 12;

    for i in 1..v_loan.term_months loop
      v_interest := round(v_balance * v_monthly_rate, 2);
      v_principal := round(v_loan.installment_amount - v_interest, 2);
      v_balance := round(v_balance - v_principal, 2);
      if i = v_loan.term_months then v_balance := 0; end if;

      insert into loan_amortization_schedule (loan_id, period_number, due_date, installment, interest, principal, balance)
      values (p_loan_id, i, (v_loan.next_deduction_date + ((i - 1) || ' months')::interval)::date,
              v_loan.installment_amount, v_interest, v_principal, v_balance);
    end loop;
  end if;
end;
$$;

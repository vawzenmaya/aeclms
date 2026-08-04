-- ============================================================
-- APPLICATION FORM FIELDS + DTI CAP BECOMES A FLAG, NOT A BLOCK
-- Run this AFTER 01 through 05.
-- ============================================================

-- ---------- 1. Employee number lives on the profile (members only), reused every application ----------
alter table profiles add column employee_number text unique;
-- e.g. 'AEC/00231' — assign this once per member (via Table Editor or an admin screen later).

-- ---------- 2. Application form fields on loans ----------
alter table loans add column category text not null default 'member'
  check (category in ('member','non_member'));
alter table loans add column employee_number text;         -- copied from profile for members, typed for non-members
alter table loans add column full_name text;                -- snapshot at application time (form asks for it explicitly)
alter table loans add column email text;
alter table loans add column phone text;
alter table loans add column amount_in_words text;           -- auto-filled client-side, editable
alter table loans add column security_description text;      -- "security's name" where necessary
alter table loans add column security_estimated_value numeric(14,2);
alter table loans add column interest_method text not null default 'reducing_balance';

-- Guarantor (captured as written on the form; can be upgraded to a digital confirmation step later)
alter table loans add column guarantor_name text;
alter table loans add column guarantor_email text;
alter table loans add column guarantor_phone text;
alter table loans add column guarantor_confirmed_at timestamptz;

-- Bank details for RTGS disbursement — required before a loan can be submitted
alter table loans add column bank_account_holder_name text;
alter table loans add column bank_name text;
alter table loans add column bank_account_number text;
alter table loans add column bank_sort_code text;
alter table loans add column bank_swift_code text;
alter table loans add column bank_details_confirmed boolean not null default false;

-- ---------- 3. DTI ratio becomes a visible flag, not a hard stop ----------
alter table loans add column dti_exceeded boolean not null default false;

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
    new.dti_exceeded := new.debt_to_income_ratio > v_settings.max_debt_to_income_ratio;
  else
    new.debt_to_income_ratio := null;
    new.dti_exceeded := false;
  end if;

  -- auto-fill employee number for members from their profile, if not already set
  if new.category = 'member' and new.employee_number is null then
    select employee_number into new.employee_number from profiles where id = new.applicant_id;
  end if;

  return new;
end;
$$;

-- ---------- 4. Submission no longer blocks on DTI — it only requires bank details + net pay/term ----------
drop trigger if exists b_loan_submission on loans;

create or replace function handle_loan_submission()
returns trigger language plpgsql security definer as $$
declare
  v_stage workflow_stages%rowtype;
begin
  if new.status = 'in_review' and old.status in ('draft','returned_to_applicant') then

    if new.net_pay is null or new.term_months is null then
      raise exception 'Net pay and loan period must be provided before submitting.';
    end if;

    if not new.bank_details_confirmed
       or new.bank_account_holder_name is null or new.bank_name is null
       or new.bank_account_number is null or new.bank_swift_code is null then
      raise exception 'Bank details must be filled in and confirmed before submitting (needed for disbursement).';
    end if;

    -- Note: dti_exceeded is intentionally NOT checked here.
    -- An over-ratio application still submits; the committee sees it flagged red
    -- at every stage and decides for themselves.

    new.current_stage_order := 1;
    new.submitted_at := now();

    select * into v_stage from workflow_stages
      where template_id = new.template_id and stage_order = 1;

    perform notify_role_holders(
      new.community_id, v_stage.role_id, new.id,
      'New loan application',
      'A loan application from ' || (select full_name from profiles where id = new.applicant_id)
        || ' is waiting at your stage (' || v_stage.stage_name || ').'
        || case when new.dti_exceeded then ' Note: repayment exceeds the 20% affordability guideline.' else '' end
    );
  end if;
  return new;
end;
$$;

create trigger b_loan_submission
  before update on loans
  for each row execute function handle_loan_submission();

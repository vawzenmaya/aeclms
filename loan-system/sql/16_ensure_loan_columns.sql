-- ============================================================
-- FIX: "column does not exist" errors mean some ALTER TABLE ADD COLUMN
-- statements from earlier files never actually landed (most likely the
-- original big multi-statement paste stopped partway after an earlier
-- error, silently skipping everything after it in that same run).
--
-- This file is safe to run any number of times: every statement uses
-- IF NOT EXISTS, so already-present columns are simply skipped and
-- only genuinely missing ones get added. Run this once now, and again
-- any time you suspect the schema and the SQL files have drifted apart.
-- ============================================================

-- from 03_reject_flow_and_notifications.sql
alter table loans add column if not exists parent_loan_id uuid references loans(id);

-- from 04_repayments.sql
alter table loans add column if not exists installment_amount numeric(14,2);
alter table loans add column if not exists next_deduction_date date;
alter table loans add column if not exists outstanding_balance numeric(14,2);
alter table loans add column if not exists completed_at timestamptz;
alter table loan_stage_actions add column if not exists installment_amount numeric(14,2);
alter table loan_stage_actions add column if not exists first_deduction_date date;

-- from 05_repayment_calculation.sql
alter table loans add column if not exists net_pay numeric(14,2);
alter table loans add column if not exists term_months int;
alter table loans add column if not exists application_date date not null default current_date;
alter table loans add column if not exists expected_end_date date;
alter table loans add column if not exists interest_rate numeric(6,3);
alter table loans add column if not exists processing_fee numeric(14,2);
alter table loans add column if not exists debt_to_income_ratio numeric(6,4);

-- from 06_application_form_fields.sql
alter table loans add column if not exists category text not null default 'member';
alter table loans add column if not exists employee_number text;
alter table loans add column if not exists full_name text;
alter table loans add column if not exists email text;
alter table loans add column if not exists phone text;
alter table loans add column if not exists amount_in_words text;
alter table loans add column if not exists security_description text;
alter table loans add column if not exists security_estimated_value numeric(14,2);
alter table loans add column if not exists interest_method text not null default 'reducing_balance';
alter table loans add column if not exists guarantor_name text;
alter table loans add column if not exists guarantor_email text;
alter table loans add column if not exists guarantor_phone text;
alter table loans add column if not exists guarantor_confirmed_at timestamptz;
alter table loans add column if not exists bank_account_holder_name text;
alter table loans add column if not exists bank_name text;
alter table loans add column if not exists bank_account_number text;
alter table loans add column if not exists bank_sort_code text;
alter table loans add column if not exists bank_swift_code text;
alter table loans add column if not exists bank_details_confirmed boolean not null default false;
alter table loans add column if not exists dti_exceeded boolean not null default false;

-- from 07_guarantor_confirmation.sql
alter table loans add column if not exists guarantor_id uuid references profiles(id);
alter table loans add column if not exists guarantor_response text not null default 'pending';
alter table loans add column if not exists guarantor_responded_at timestamptz;
alter table loans add column if not exists guarantor_decline_reason text;

-- from 08_loan_categories.sql
alter table loans add column if not exists loan_category text not null default 'normal';

-- ---------- Re-attach the CHECK constraints, skipping if already present ----------
do $$
begin
  alter table loans add constraint loans_category_check check (category in ('member','non_member'));
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table loans add constraint loans_guarantor_response_check check (guarantor_response in ('pending','confirmed','declined'));
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table loans add constraint loans_loan_category_check check (loan_category in ('emergency','normal'));
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table loans add constraint topup_only_for_normal check (loan_type <> 'topup' or loan_category = 'normal');
exception when duplicate_object then null;
end $$;

-- ---------- Confirm: list every column loans has right now ----------
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_name = 'loans'
order by ordinal_position;

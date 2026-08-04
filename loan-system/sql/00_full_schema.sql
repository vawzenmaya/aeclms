-- ============================================================
-- LOAN MANAGEMENT SYSTEM -- FULL DATABASE SETUP (run once, top to bottom)
-- Combines files 01-17. Paste this whole file into Supabase SQL Editor
-- and run it as a single query. Keep the numbered files for reference
-- if you ever want to see what each stage of development added.
-- ============================================================


-- ############################################################
-- FILE: 01_schema.sql
-- ############################################################
-- ============================================================
-- LOAN MANAGEMENT SYSTEM — CORE SCHEMA
-- Run this in Supabase Dashboard → SQL Editor → New query
-- ============================================================

-- ---------- Extensions ----------
create extension if not exists "uuid-ossp";

-- ============================================================
-- 1. COMMUNITIES
-- ============================================================
create table communities (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now()
);

-- ============================================================
-- 2. PROFILES (extends auth.users)
-- ============================================================
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  community_id uuid references communities(id),
  full_name text not null,
  phone text,
  avatar_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ============================================================
-- 3. ROLES (reference table — not per-user, just the catalog)
-- ============================================================
create table roles (
  id smallint primary key,
  code text unique not null,   -- machine-readable
  label text not null          -- human-readable
);

insert into roles (id, code, label) values
  (1, 'member', 'Member'),
  (2, 'loan_officer', 'Loan Officer'),
  (3, 'loan_reviewer', 'Loan Reviewer'),
  (4, 'committee_chairperson', 'Loan Committee Chairperson'),
  (5, 'general_secretary', 'General Secretary'),
  (6, 'treasurer', 'Treasurer'),
  (7, 'community_chairperson', 'Community Chairperson'),
  (8, 'auditor', 'Auditor'),
  (9, 'ex_officio', 'Ex-Officio');

-- ============================================================
-- 4. USER_ROLES (who holds what role, in which community)
--    A person can hold multiple roles; roles are scoped to a community
-- ============================================================
create table user_roles (
  id uuid primary key default uuid_generate_v4(),
  profile_id uuid not null references profiles(id) on delete cascade,
  role_id smallint not null references roles(id),
  community_id uuid not null references communities(id),
  is_active boolean not null default true,
  assigned_at timestamptz not null default now(),
  unique (profile_id, role_id, community_id)
);

-- ============================================================
-- 5. WORKFLOW TEMPLATES & STAGES
--    Defines the ORDER of approval for a loan type.
--    Treasurer appears twice (review, then disbursement) — that's fine,
--    each row is just a distinct stage pointing at the same role.
-- ============================================================
create table workflow_templates (
  id uuid primary key default uuid_generate_v4(),
  loan_type text not null check (loan_type in ('new', 'topup')),
  name text not null,
  is_active boolean not null default true
);

create table workflow_stages (
  id uuid primary key default uuid_generate_v4(),
  template_id uuid not null references workflow_templates(id) on delete cascade,
  stage_order int not null,
  role_id smallint not null references roles(id),
  stage_name text not null,       -- e.g. "Treasurer Review" vs "Treasurer Disbursement"
  is_disbursement_stage boolean not null default false,
  unique (template_id, stage_order)
);

-- Seed one workflow template used for both new + topup loans (identical flow for now)
insert into workflow_templates (id, loan_type, name) values
  ('00000000-0000-0000-0000-000000000001', 'new',   'Standard New Loan Workflow'),
  ('00000000-0000-0000-0000-000000000002', 'topup', 'Standard Top-up Loan Workflow');

insert into workflow_stages (template_id, stage_order, role_id, stage_name, is_disbursement_stage)
select t.id, s.stage_order, s.role_id, s.stage_name, s.is_disbursement_stage
from (values
  (1, 2, 'Loan Officer Review', false),
  (2, 3, 'Loan Reviewer Review', false),
  (3, 4, 'Committee Chairperson Approval', false),
  (4, 5, 'General Secretary Approval', false),
  (5, 6, 'Treasurer Review', false),
  (6, 7, 'Community Chairperson Approval', false),
  (7, 8, 'Auditor Approval', false),
  (8, 9, 'Ex-Officio Approval', false),
  (9, 6, 'Treasurer Disbursement', true)
) as s(stage_order, role_id, stage_name, is_disbursement_stage)
cross join workflow_templates t;
-- (this inserts the same 9 stages for BOTH templates above; fine since flow is identical)

-- ============================================================
-- 6. LOANS
-- ============================================================
create table loans (
  id uuid primary key default uuid_generate_v4(),
  applicant_id uuid not null references profiles(id),
  community_id uuid not null references communities(id),
  template_id uuid not null references workflow_templates(id),
  loan_type text not null check (loan_type in ('new', 'topup')),
  amount_requested numeric(14,2) not null,
  amount_disbursed numeric(14,2),
  purpose text,
  status text not null default 'submitted'
    check (status in ('draft','submitted','in_review','returned','rejected','approved','disbursed')),
  current_stage_order int not null default 1,
  submitted_at timestamptz,
  disbursed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 7. LOAN DOCUMENTS (uploaded forms/files — stored in Supabase Storage)
-- ============================================================
create table loan_documents (
  id uuid primary key default uuid_generate_v4(),
  loan_id uuid not null references loans(id) on delete cascade,
  doc_type text not null,          -- e.g. 'application_form', 'id_copy', 'payslip'
  storage_path text not null,      -- path inside the storage bucket
  uploaded_by uuid not null references profiles(id),
  uploaded_at timestamptz not null default now()
);

-- ============================================================
-- 8. LOAN STAGE ACTIONS (the audit trail of approvals/rejections)
-- ============================================================
create table loan_stage_actions (
  id uuid primary key default uuid_generate_v4(),
  loan_id uuid not null references loans(id) on delete cascade,
  stage_id uuid not null references workflow_stages(id),
  actor_id uuid not null references profiles(id),
  action text not null check (action in ('approved','rejected','returned')),
  comment text,
  acted_at timestamptz not null default now()
);

-- ============================================================
-- 9. NOTIFICATIONS
-- ============================================================
create table notifications (
  id uuid primary key default uuid_generate_v4(),
  recipient_id uuid not null references profiles(id) on delete cascade,
  loan_id uuid references loans(id) on delete cascade,
  title text not null,
  body text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

-- ============================================================
-- Helpful indexes
-- ============================================================
create index idx_loans_applicant on loans(applicant_id);
create index idx_loans_status on loans(status);
create index idx_user_roles_profile on user_roles(profile_id);
create index idx_notifications_recipient on notifications(recipient_id, is_read);
create index idx_stage_actions_loan on loan_stage_actions(loan_id);


-- ############################################################
-- FILE: 02_security_and_triggers.sql
-- ############################################################
-- ============================================================
-- ROW LEVEL SECURITY + TRIGGERS
-- Run this AFTER 01_schema.sql
-- ============================================================

-- ---------- Enable RLS everywhere ----------
alter table profiles enable row level security;
alter table user_roles enable row level security;
alter table loans enable row level security;
alter table loan_documents enable row level security;
alter table loan_stage_actions enable row level security;
alter table notifications enable row level security;

-- ---------- Helper: does the current user hold role X in a community? ----------
create or replace function has_role(p_role_code text, p_community_id uuid)
returns boolean
language sql stable security definer
as $$
  select exists (
    select 1
    from user_roles ur
    join roles r on r.id = ur.role_id
    where ur.profile_id = auth.uid()
      and ur.community_id = p_community_id
      and ur.is_active = true
      and r.code = p_role_code
  );
$$;

-- ---------- Helper: is the current user the assigned approver for a loan's CURRENT stage? ----------
create or replace function is_current_stage_approver(p_loan_id uuid)
returns boolean
language sql stable security definer
as $$
  select exists (
    select 1
    from loans l
    join workflow_stages ws on ws.template_id = l.template_id and ws.stage_order = l.current_stage_order
    join roles r on r.id = ws.role_id
    join user_roles ur on ur.role_id = r.id and ur.community_id = l.community_id and ur.is_active = true
    where l.id = p_loan_id
      and ur.profile_id = auth.uid()
  );
$$;

-- ============================================================
-- PROFILES: everyone in the same community can see each other's basic profile
-- ============================================================
create policy "profiles: view same community"
  on profiles for select
  using (community_id = (select community_id from profiles where id = auth.uid()));

create policy "profiles: update own"
  on profiles for update
  using (id = auth.uid());

-- ============================================================
-- USER_ROLES: visible to everyone in the community (so applicants know who holds what)
-- ============================================================
create policy "user_roles: view same community"
  on user_roles for select
  using (community_id = (select community_id from profiles where id = auth.uid()));

-- (Assigning roles should go through an admin-only Edge Function / dashboard tool,
--  not directly from the app — no insert/update policy given here on purpose.)

-- ============================================================
-- LOANS
--   - applicant can see their own loans
--   - the current-stage approver can see the loan
--   - anyone who has ever acted on the loan can still see it (history)
--   - applicants can insert their own loan applications
-- ============================================================
create policy "loans: applicant can view own"
  on loans for select
  using (applicant_id = auth.uid());

create policy "loans: current approver can view"
  on loans for select
  using (is_current_stage_approver(id));

create policy "loans: past actors can view"
  on loans for select
  using (exists (
    select 1 from loan_stage_actions a where a.loan_id = loans.id and a.actor_id = auth.uid()
  ));

create policy "loans: applicant can insert"
  on loans for insert
  with check (applicant_id = auth.uid());

create policy "loans: current approver can update"
  on loans for update
  using (is_current_stage_approver(id));

-- ============================================================
-- LOAN_DOCUMENTS: visible to whoever can see the parent loan
-- ============================================================
create policy "loan_documents: visible with loan"
  on loan_documents for select
  using (exists (
    select 1 from loans l where l.id = loan_documents.loan_id
    and (l.applicant_id = auth.uid() or is_current_stage_approver(l.id))
  ));

create policy "loan_documents: applicant can insert"
  on loan_documents for insert
  with check (exists (
    select 1 from loans l where l.id = loan_documents.loan_id and l.applicant_id = auth.uid()
  ));

-- ============================================================
-- LOAN_STAGE_ACTIONS: audit trail — visible to applicant + anyone involved
-- ============================================================
create policy "stage_actions: visible with loan"
  on loan_stage_actions for select
  using (exists (
    select 1 from loans l where l.id = loan_stage_actions.loan_id
    and (l.applicant_id = auth.uid() or is_current_stage_approver(l.id))
  ) or actor_id = auth.uid());

create policy "stage_actions: current approver can insert"
  on loan_stage_actions for insert
  with check (is_current_stage_approver(loan_id) and actor_id = auth.uid());

-- ============================================================
-- NOTIFICATIONS: only the recipient can see/update their own
-- ============================================================
create policy "notifications: recipient can view"
  on notifications for select
  using (recipient_id = auth.uid());

create policy "notifications: recipient can mark read"
  on notifications for update
  using (recipient_id = auth.uid());

-- ============================================================
-- TRIGGERS
-- ============================================================

-- 1) Auto-create a profile row whenever a new auth user signs up
create or replace function handle_new_user()
returns trigger
language plpgsql security definer
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.email));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- 2) Keep loans.updated_at fresh
create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger loans_set_updated_at
  before update on loans
  for each row execute function set_updated_at();

-- 3) When a stage action is inserted, advance (or stop) the loan automatically
create or replace function process_stage_action()
returns trigger
language plpgsql security definer
as $$
declare
  v_loan loans%rowtype;
  v_max_stage int;
  v_next_role_id smallint;
  v_next_stage_name text;
begin
  select * into v_loan from loans where id = new.loan_id;

  if new.action = 'rejected' then
    update loans set status = 'rejected' where id = new.loan_id;

  elsif new.action = 'returned' then
    update loans set status = 'returned' where id = new.loan_id;

  elsif new.action = 'approved' then
    select max(stage_order) into v_max_stage
    from workflow_stages where template_id = v_loan.template_id;

    if v_loan.current_stage_order >= v_max_stage then
      -- this was the disbursement stage
      update loans
        set status = 'disbursed', disbursed_at = now(), amount_disbursed = coalesce(amount_disbursed, amount_requested)
        where id = new.loan_id;
    else
      update loans
        set current_stage_order = current_stage_order + 1, status = 'in_review'
        where id = new.loan_id;
    end if;
  end if;

  return new;
end;
$$;

create trigger on_stage_action_process
  after insert on loan_stage_actions
  for each row execute function process_stage_action();


-- ############################################################
-- FILE: 03_reject_flow_and_notifications.sql
-- ############################################################
-- ============================================================
-- WORKFLOW UPDATE: reject-to-previous-stage + notifications + draft state
-- Run this AFTER 01_schema.sql and 02_security_and_triggers.sql
-- ============================================================

-- ---------- 1. Loans: add draft state + topup linkage ----------
alter table loans drop constraint loans_status_check;
alter table loans add constraint loans_status_check
  check (status in ('draft','in_review','returned_to_applicant','rejected','approved','disbursed'));
-- 'rejected' kept only for a possible future "hard stop" scenario (e.g. fraud) — normal
-- flow now uses 'returned_to_applicant' instead of a dead-end rejection.

alter table loans alter column status set default 'draft';
alter table loans add column parent_loan_id uuid references loans(id);
-- for topups: points at the original loan being topped up

-- ---------- 2. Loan stage actions: drop 'returned', require comment on reject ----------
alter table loan_stage_actions drop constraint loan_stage_actions_action_check;
alter table loan_stage_actions add constraint loan_stage_actions_action_check
  check (action in ('approved','rejected'));

alter table loan_stage_actions add constraint reject_requires_comment
  check (action <> 'rejected' or (comment is not null and length(trim(comment)) > 0));

-- ---------- 3. Applicant can update their own loan while draft/returned ----------
create policy "loans: applicant can update while editable"
  on loans for update
  using (applicant_id = auth.uid() and status in ('draft','returned_to_applicant'));

-- ---------- 4. Notification helpers ----------
create or replace function notify_role_holders(
  p_community_id uuid, p_role_id smallint, p_loan_id uuid, p_title text, p_body text
) returns void language plpgsql security definer as $$
begin
  insert into notifications (recipient_id, loan_id, title, body)
  select ur.profile_id, p_loan_id, p_title, p_body
  from user_roles ur
  where ur.community_id = p_community_id
    and ur.role_id = p_role_id
    and ur.is_active = true;
end;
$$;

create or replace function notify_applicant(p_loan_id uuid, p_title text, p_body text)
returns void language plpgsql security definer as $$
begin
  insert into notifications (recipient_id, loan_id, title, body)
  select applicant_id, p_loan_id, p_title, p_body from loans where id = p_loan_id;
end;
$$;

create or replace function notify_all_past_actors(p_loan_id uuid, p_title text, p_body text)
returns void language plpgsql security definer as $$
begin
  insert into notifications (recipient_id, loan_id, title, body)
  select distinct actor_id, p_loan_id, p_title, p_body
  from loan_stage_actions where loan_id = p_loan_id;
end;
$$;

-- ---------- 5. Notify Stage 1 when a loan is submitted (draft/returned -> in_review) ----------
create or replace function handle_loan_submission()
returns trigger language plpgsql security definer as $$
declare
  v_stage workflow_stages%rowtype;
begin
  if new.status = 'in_review' and old.status in ('draft','returned_to_applicant') then
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

create trigger on_loan_submission
  before update on loans
  for each row execute function handle_loan_submission();

-- ---------- 6. Replace the approve/reject processor with the new behavior ----------
drop trigger if exists on_stage_action_process on loan_stage_actions;
drop function if exists process_stage_action();

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
      -- no one before the Loan Officer -> back to the applicant to fix & resubmit
      update loans set status = 'returned_to_applicant' where id = new.loan_id;
      perform notify_applicant(
        new.loan_id, 'Loan sent back to you',
        v_current_stage.stage_name || ' returned your application: ' || new.comment
      );
    else
      -- back one stage to whoever handled it previously
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
      update loans
        set status = 'disbursed', disbursed_at = now(),
            amount_disbursed = coalesce(amount_disbursed, amount_requested)
        where id = new.loan_id;

      perform notify_applicant(new.loan_id, 'Loan disbursed',
        'Your loan of ' || v_loan.amount_requested || ' has been disbursed.');
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

create trigger on_stage_action_process
  after insert on loan_stage_actions
  for each row execute function process_stage_action();


-- ############################################################
-- FILE: 04_repayments.sql
-- ############################################################
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


-- ############################################################
-- FILE: 05_repayment_calculation.sql
-- ############################################################
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


-- ############################################################
-- FILE: 06_application_form_fields.sql
-- ############################################################
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


-- ############################################################
-- FILE: 07_guarantor_confirmation.sql
-- ############################################################
-- ============================================================
-- DIGITAL GUARANTOR CONFIRMATION
-- Run this AFTER 01 through 06.
-- ============================================================

-- ---------- 1. Guarantor becomes a real community member reference ----------
alter table loans add column guarantor_id uuid references profiles(id);
alter table loans add column guarantor_response text not null default 'pending'
  check (guarantor_response in ('pending','confirmed','declined'));
alter table loans add column guarantor_responded_at timestamptz;
alter table loans add column guarantor_decline_reason text;
-- guarantor_name / guarantor_email / guarantor_phone (added in 06) now act as an
-- auto-filled snapshot of the chosen guarantor's profile, for the printed form.

-- ---------- 2. New status: sits between "ready to submit" and "with the committee" ----------
alter table loans drop constraint loans_status_check;
alter table loans add constraint loans_status_check
  check (status in ('draft','awaiting_guarantor','in_review','returned_to_applicant',
                     'rejected','approved','disbursed','completed'));

-- ---------- 3. Auto-fill the guarantor's snapshot fields when one is picked ----------
create or replace function snapshot_guarantor_details()
returns trigger language plpgsql security definer as $$
begin
  if new.guarantor_id is not null and (old.guarantor_id is distinct from new.guarantor_id) then
    select full_name, email, phone
      into new.guarantor_name, new.guarantor_email, new.guarantor_phone
      from profiles where id = new.guarantor_id;
    new.guarantor_response := 'pending';
    new.guarantor_responded_at := null;
  end if;
  return new;
end;
$$;

create trigger a2_snapshot_guarantor
  before insert or update of guarantor_id on loans
  for each row execute function snapshot_guarantor_details();

-- ---------- 4. Guarantor can see the loan they're asked to guarantee ----------
create policy "loans: guarantor can view"
  on loans for select
  using (guarantor_id = auth.uid());

-- ---------- 5. Rewire submission: route through the guarantor first, if one is set ----------
drop trigger if exists b_loan_submission on loans;

create or replace function handle_loan_submission()
returns trigger language plpgsql security definer as $$
declare
  v_stage workflow_stages%rowtype;
begin

  -- Step A: applicant submits a draft/returned loan
  if new.status in ('awaiting_guarantor','in_review') and old.status in ('draft','returned_to_applicant') then

    if new.net_pay is null or new.term_months is null then
      raise exception 'Net pay and loan period must be provided before submitting.';
    end if;

    if not new.bank_details_confirmed
       or new.bank_account_holder_name is null or new.bank_name is null
       or new.bank_account_number is null or new.bank_swift_code is null then
      raise exception 'Bank details must be filled in and confirmed before submitting (needed for disbursement).';
    end if;

    new.submitted_at := now();

    if new.guarantor_id is not null then
      -- Route to the guarantor first
      new.status := 'awaiting_guarantor';
      new.guarantor_response := 'pending';
      insert into notifications (recipient_id, loan_id, title, body)
      values (new.guarantor_id, new.id, 'Guarantee request',
        (select full_name from profiles where id = new.applicant_id)
          || ' has asked you to guarantee their loan of ' || new.amount_requested
          || '. Please confirm or decline in the app.');
    else
      -- No guarantor required for this loan -> straight to the committee
      new.status := 'in_review';
      new.current_stage_order := 1;
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
  end if;

  return new;
end;
$$;

create trigger b_loan_submission
  before update on loans
  for each row execute function handle_loan_submission();

-- ---------- 6. The guarantor's confirm/decline action (called via RPC, not a raw table update) ----------
create or replace function guarantor_respond(p_loan_id uuid, p_confirm boolean, p_comment text default null)
returns void language plpgsql security definer as $$
declare
  v_loan loans%rowtype;
  v_stage workflow_stages%rowtype;
begin
  select * into v_loan from loans where id = p_loan_id;

  if v_loan.guarantor_id is distinct from auth.uid() then
    raise exception 'Only the assigned guarantor can respond to this request.';
  end if;
  if v_loan.status <> 'awaiting_guarantor' then
    raise exception 'This loan is not currently awaiting guarantor confirmation.';
  end if;

  if p_confirm then
    select * into v_stage from workflow_stages
      where template_id = v_loan.template_id and stage_order = 1;

    update loans set
      guarantor_response = 'confirmed',
      guarantor_responded_at = now(),
      status = 'in_review',
      current_stage_order = 1
    where id = p_loan_id;

    perform notify_role_holders(
      v_loan.community_id, v_stage.role_id, p_loan_id,
      'New loan application',
      (select full_name from profiles where id = v_loan.applicant_id)
        || '''s loan has been guaranteed and is now waiting at your stage (' || v_stage.stage_name || ').'
        || case when v_loan.dti_exceeded then ' Note: repayment exceeds the 20% affordability guideline.' else '' end
    );
    perform notify_applicant(p_loan_id, 'Guarantor confirmed',
      'Your guarantor has confirmed. Your application has moved to the committee.');
  else
    if p_comment is null or length(trim(p_comment)) = 0 then
      raise exception 'A reason is required when declining to guarantee a loan.';
    end if;

    update loans set
      guarantor_response = 'declined',
      guarantor_responded_at = now(),
      guarantor_decline_reason = p_comment,
      status = 'returned_to_applicant'
    where id = p_loan_id;

    perform notify_applicant(p_loan_id, 'Guarantor declined',
      'Your guarantor declined to guarantee this loan: ' || p_comment
        || '. Please choose a different guarantor and resubmit.');
  end if;
end;
$$;


-- ############################################################
-- FILE: 08_loan_categories.sql
-- ############################################################
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


-- ############################################################
-- FILE: 09_profile_self_view_fix.sql
-- ############################################################
-- ============================================================
-- FIX: users must always be able to see their OWN profile row,
-- even before an admin has assigned them to a community.
--
-- Why: the existing "profiles: view same community" policy compares
-- community_id = (their own community_id). When that's NULL (brand new
-- signup, not yet assigned), NULL = NULL evaluates to UNKNOWN in SQL,
-- not true -- so the row is invisible even to its own owner. This adds
-- a second, unconditional policy just for viewing your own row.
-- Run this AFTER 00_full_schema.sql / after file 08.
-- ============================================================

create policy "profiles: view own"
  on profiles for select
  using (id = auth.uid());


-- ############################################################
-- FILE: 10_fix_profiles_recursion.sql
-- ############################################################
-- ============================================================
-- FIX: infinite recursion (42P17) in the "profiles: view same community" policy.
--
-- Why it happened: that policy's USING clause ran a SELECT on `profiles`
-- to find your own community_id -- and that inner SELECT is itself
-- subject to the same policy, which runs the inner SELECT again, forever.
--
-- Fix: move the lookup into a SECURITY DEFINER function. Functions like
-- this run as the function owner (the table owner, e.g. `postgres`),
-- which bypasses RLS entirely by default -- so the inner lookup no
-- longer re-triggers the policy.
-- Run this AFTER 00_full_schema.sql / after file 09.
-- ============================================================

create or replace function my_profile_community_id()
returns uuid
language sql stable security definer
set search_path = public
as $$
  select community_id from profiles where id = auth.uid();
$$;

drop policy if exists "profiles: view same community" on profiles;

create policy "profiles: view same community"
  on profiles for select
  using (community_id = my_profile_community_id());


-- ############################################################
-- FILE: 11_fix_applicant_submit_check.sql
-- ############################################################
-- ============================================================
-- FIX: the applicant's "edit while draft/returned" policy had no
-- explicit WITH CHECK, so Postgres defaulted it to the same condition
-- as the read check -- which would have blocked the exact update that
-- submits a loan (since submitting changes status AWAY FROM draft).
-- Run this AFTER 00_full_schema.sql / after file 10.
-- ============================================================

drop policy if exists "loans: applicant can update while editable" on loans;

create policy "loans: applicant can update while editable"
  on loans for update
  using (applicant_id = auth.uid() and status in ('draft','returned_to_applicant'))
  with check (applicant_id = auth.uid());


-- ############################################################
-- FILE: 12_fix_guarantor_trigger_on_insert.sql
-- ############################################################
-- ============================================================
-- FIX: snapshot_guarantor_details() referenced OLD.guarantor_id
-- unconditionally, but OLD does not exist during an INSERT (only UPDATE).
-- This could throw "record \"old\" is not assigned yet" on every new
-- loan application, guarantor or not. Rewritten to branch on TG_OP
-- explicitly instead of relying on OR short-circuiting (which Postgres
-- does not guarantee for general boolean expressions).
-- Run this AFTER 00_full_schema.sql / after file 11.
-- ============================================================

create or replace function snapshot_guarantor_details()
returns trigger language plpgsql security definer as $$
begin
  if tg_op = 'INSERT' then
    if new.guarantor_id is not null then
      select full_name, email, phone
        into new.guarantor_name, new.guarantor_email, new.guarantor_phone
        from profiles where id = new.guarantor_id;
      new.guarantor_response := 'pending';
      new.guarantor_responded_at := null;
    end if;
  elsif tg_op = 'UPDATE' then
    if new.guarantor_id is not null and old.guarantor_id is distinct from new.guarantor_id then
      select full_name, email, phone
        into new.guarantor_name, new.guarantor_email, new.guarantor_phone
        from profiles where id = new.guarantor_id;
      new.guarantor_response := 'pending';
      new.guarantor_responded_at := null;
    end if;
  end if;
  return new;
end;
$$;


-- ############################################################
-- FILE: 13_fix_missing_grants.sql
-- ############################################################
-- ============================================================
-- FIX: missing table-level grants for the `authenticated` role.
--
-- Why: workflow_templates, workflow_stages, roles, communities, and
-- loan_settings never had `alter table ... enable row level security`
-- run on them (deliberately -- they're reference/lookup data, not
-- per-user data). But tables created via the SQL Editor don't
-- automatically pick up the default GRANTs that Supabase sets up for
-- tables created through the dashboard UI, so `authenticated` had no
-- SELECT permission on them at all -- confirmed by testing as that role.
-- Run this once.
-- ============================================================

grant select on workflow_templates to authenticated;
grant select on workflow_stages to authenticated;
grant select on roles to authenticated;
grant select on communities to authenticated;
grant select on loan_settings to authenticated;

-- Also make sure any future tables you create the same way don't hit
-- this again -- this sets the default for new tables in the public schema:
alter default privileges in schema public grant select on tables to authenticated;


-- ############################################################
-- FILE: 14_fix_reference_table_rls.sql
-- ############################################################
-- ============================================================
-- FIX: these are shared reference/lookup tables (not per-user data),
-- so they were never meant to have RLS restricting them -- but RLS may
-- have been switched on for one or more of them at some point (e.g. via
-- a dashboard "Enable RLS" prompt) with no policy attached, which means
-- DEFAULT DENY for every role except the table owner. That matches
-- exactly what we're seeing: `postgres` sees rows (bypasses RLS),
-- `authenticated` has the GRANT but gets 0 rows back (blocked by RLS).
--
-- Run the check first to see current state, then the fixes below.
-- ============================================================

-- ---------- Check current RLS status (run this first, look at the results) ----------
select relname, relrowsecurity, relforcerowsecurity
from pg_class
where relname in ('workflow_templates', 'workflow_stages', 'roles', 'communities', 'loan_settings');

-- ---------- Fix: make sure RLS is on, and add an explicit "authenticated can read" policy ----------
-- These are safe to expose read-only to any logged-in user -- they contain no
-- personal data, just shared configuration (workflow order, role names, interest
-- rate settings).

alter table workflow_templates enable row level security;
drop policy if exists "workflow_templates: readable by authenticated" on workflow_templates;
create policy "workflow_templates: readable by authenticated"
  on workflow_templates for select
  to authenticated
  using (true);

alter table workflow_stages enable row level security;
drop policy if exists "workflow_stages: readable by authenticated" on workflow_stages;
create policy "workflow_stages: readable by authenticated"
  on workflow_stages for select
  to authenticated
  using (true);

alter table roles enable row level security;
drop policy if exists "roles: readable by authenticated" on roles;
create policy "roles: readable by authenticated"
  on roles for select
  to authenticated
  using (true);

alter table communities enable row level security;
drop policy if exists "communities: readable by authenticated" on communities;
create policy "communities: readable by authenticated"
  on communities for select
  to authenticated
  using (true);

alter table loan_settings enable row level security;
drop policy if exists "loan_settings: readable by authenticated" on loan_settings;
create policy "loan_settings: readable by authenticated"
  on loan_settings for select
  to authenticated
  using (true);


-- ############################################################
-- FILE: 15_fix_loans_stage_actions_recursion.sql
-- ############################################################
-- ============================================================
-- FIX: infinite recursion (42P17) caused by a CROSS-TABLE cycle:
--   loans."past actors can view"       -> queries loan_stage_actions
--   loan_stage_actions."visible with loan" -> queries loans
-- Neither side had a bypass, so checking one table's policy required
-- checking the other's, which required checking the first again, etc.
--
-- Fix: wrap each cross-table check in its own SECURITY DEFINER function,
-- same pattern as the earlier profiles recursion fix -- this breaks the
-- cycle because a SECURITY DEFINER function (owned by the table owner)
-- bypasses RLS on its own internal query.
-- Run this AFTER 00_full_schema.sql / after file 14.
-- ============================================================

-- ---------- Breaks the loans -> loan_stage_actions leg ----------
create or replace function has_acted_on_loan(p_loan_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from loan_stage_actions a where a.loan_id = p_loan_id and a.actor_id = auth.uid()
  );
$$;

drop policy if exists "loans: past actors can view" on loans;
create policy "loans: past actors can view"
  on loans for select
  using (has_acted_on_loan(id));

-- ---------- Breaks the loan_stage_actions -> loans leg ----------
create or replace function loan_visible_to_current_user(p_loan_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from loans l where l.id = p_loan_id
    and (l.applicant_id = auth.uid() or is_current_stage_approver(l.id))
  );
$$;

drop policy if exists "stage_actions: visible with loan" on loan_stage_actions;
create policy "stage_actions: visible with loan"
  on loan_stage_actions for select
  using (loan_visible_to_current_user(loan_id) or actor_id = auth.uid());

-- ---------- Hygiene: pin search_path on the existing bypass function too ----------
create or replace function is_current_stage_approver(p_loan_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1
    from loans l
    join workflow_stages ws on ws.template_id = l.template_id and ws.stage_order = l.current_stage_order
    join roles r on r.id = ws.role_id
    join user_roles ur on ur.role_id = r.id and ur.community_id = l.community_id and ur.is_active = true
    where l.id = p_loan_id
      and ur.profile_id = auth.uid()
  );
$$;


-- ############################################################
-- FILE: 16_ensure_loan_columns.sql
-- ############################################################
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


-- ############################################################
-- FILE: 17_fix_guarantor_email_reference.sql
-- ############################################################
-- ============================================================
-- FIX: "column email does not exist" was never about loans.email --
-- it's the guarantor snapshot trigger trying to read `email` FROM
-- `profiles`, but profiles never had an email column (email lives on
-- Supabase's built-in auth.users table, joined via matching id).
-- This only fires when a guarantor is actually selected on the form,
-- which is why it slipped past earlier checks.
-- Run this AFTER 00_full_schema.sql / after file 16.
-- ============================================================

create or replace function snapshot_guarantor_details()
returns trigger language plpgsql security definer as $$
begin
  if tg_op = 'INSERT' then
    if new.guarantor_id is not null then
      select p.full_name, u.email, p.phone
        into new.guarantor_name, new.guarantor_email, new.guarantor_phone
        from profiles p
        join auth.users u on u.id = p.id
        where p.id = new.guarantor_id;
      new.guarantor_response := 'pending';
      new.guarantor_responded_at := null;
    end if;
  elsif tg_op = 'UPDATE' then
    if new.guarantor_id is not null and old.guarantor_id is distinct from new.guarantor_id then
      select p.full_name, u.email, p.phone
        into new.guarantor_name, new.guarantor_email, new.guarantor_phone
        from profiles p
        join auth.users u on u.id = p.id
        where p.id = new.guarantor_id;
      new.guarantor_response := 'pending';
      new.guarantor_responded_at := null;
    end if;
  end if;
  return new;
end;
$$;


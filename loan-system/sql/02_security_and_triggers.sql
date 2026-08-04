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

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

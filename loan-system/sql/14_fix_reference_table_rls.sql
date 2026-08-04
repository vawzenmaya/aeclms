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

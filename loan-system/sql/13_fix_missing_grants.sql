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

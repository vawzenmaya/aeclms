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

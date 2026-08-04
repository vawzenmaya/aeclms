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

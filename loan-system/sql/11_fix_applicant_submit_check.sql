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

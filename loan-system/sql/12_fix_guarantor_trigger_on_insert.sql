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

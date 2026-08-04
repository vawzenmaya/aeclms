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

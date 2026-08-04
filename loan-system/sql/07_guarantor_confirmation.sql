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

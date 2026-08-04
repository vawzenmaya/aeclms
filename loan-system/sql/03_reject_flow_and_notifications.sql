-- ============================================================
-- WORKFLOW UPDATE: reject-to-previous-stage + notifications + draft state
-- Run this AFTER 01_schema.sql and 02_security_and_triggers.sql
-- ============================================================

-- ---------- 1. Loans: add draft state + topup linkage ----------
alter table loans drop constraint loans_status_check;
alter table loans add constraint loans_status_check
  check (status in ('draft','in_review','returned_to_applicant','rejected','approved','disbursed'));
-- 'rejected' kept only for a possible future "hard stop" scenario (e.g. fraud) — normal
-- flow now uses 'returned_to_applicant' instead of a dead-end rejection.

alter table loans alter column status set default 'draft';
alter table loans add column parent_loan_id uuid references loans(id);
-- for topups: points at the original loan being topped up

-- ---------- 2. Loan stage actions: drop 'returned', require comment on reject ----------
alter table loan_stage_actions drop constraint loan_stage_actions_action_check;
alter table loan_stage_actions add constraint loan_stage_actions_action_check
  check (action in ('approved','rejected'));

alter table loan_stage_actions add constraint reject_requires_comment
  check (action <> 'rejected' or (comment is not null and length(trim(comment)) > 0));

-- ---------- 3. Applicant can update their own loan while draft/returned ----------
create policy "loans: applicant can update while editable"
  on loans for update
  using (applicant_id = auth.uid() and status in ('draft','returned_to_applicant'));

-- ---------- 4. Notification helpers ----------
create or replace function notify_role_holders(
  p_community_id uuid, p_role_id smallint, p_loan_id uuid, p_title text, p_body text
) returns void language plpgsql security definer as $$
begin
  insert into notifications (recipient_id, loan_id, title, body)
  select ur.profile_id, p_loan_id, p_title, p_body
  from user_roles ur
  where ur.community_id = p_community_id
    and ur.role_id = p_role_id
    and ur.is_active = true;
end;
$$;

create or replace function notify_applicant(p_loan_id uuid, p_title text, p_body text)
returns void language plpgsql security definer as $$
begin
  insert into notifications (recipient_id, loan_id, title, body)
  select applicant_id, p_loan_id, p_title, p_body from loans where id = p_loan_id;
end;
$$;

create or replace function notify_all_past_actors(p_loan_id uuid, p_title text, p_body text)
returns void language plpgsql security definer as $$
begin
  insert into notifications (recipient_id, loan_id, title, body)
  select distinct actor_id, p_loan_id, p_title, p_body
  from loan_stage_actions where loan_id = p_loan_id;
end;
$$;

-- ---------- 5. Notify Stage 1 when a loan is submitted (draft/returned -> in_review) ----------
create or replace function handle_loan_submission()
returns trigger language plpgsql security definer as $$
declare
  v_stage workflow_stages%rowtype;
begin
  if new.status = 'in_review' and old.status in ('draft','returned_to_applicant') then
    new.current_stage_order := 1;
    new.submitted_at := now();

    select * into v_stage from workflow_stages
      where template_id = new.template_id and stage_order = 1;

    perform notify_role_holders(
      new.community_id, v_stage.role_id, new.id,
      'New loan application',
      'A loan application from ' || (select full_name from profiles where id = new.applicant_id)
        || ' is waiting at your stage (' || v_stage.stage_name || ').'
    );
  end if;
  return new;
end;
$$;

create trigger on_loan_submission
  before update on loans
  for each row execute function handle_loan_submission();

-- ---------- 6. Replace the approve/reject processor with the new behavior ----------
drop trigger if exists on_stage_action_process on loan_stage_actions;
drop function if exists process_stage_action();

create or replace function process_stage_action()
returns trigger language plpgsql security definer as $$
declare
  v_loan loans%rowtype;
  v_max_stage int;
  v_current_stage workflow_stages%rowtype;
  v_target_stage workflow_stages%rowtype;
  v_applicant_name text;
begin
  select * into v_loan from loans where id = new.loan_id;
  select full_name into v_applicant_name from profiles where id = v_loan.applicant_id;

  select * into v_current_stage from workflow_stages
    where template_id = v_loan.template_id and stage_order = v_loan.current_stage_order;

  if new.action = 'rejected' then

    if v_loan.current_stage_order = 1 then
      -- no one before the Loan Officer -> back to the applicant to fix & resubmit
      update loans set status = 'returned_to_applicant' where id = new.loan_id;
      perform notify_applicant(
        new.loan_id, 'Loan sent back to you',
        v_current_stage.stage_name || ' returned your application: ' || new.comment
      );
    else
      -- back one stage to whoever handled it previously
      update loans set current_stage_order = current_stage_order - 1, status = 'in_review'
        where id = new.loan_id;

      select * into v_target_stage from workflow_stages
        where template_id = v_loan.template_id and stage_order = v_loan.current_stage_order - 1;

      perform notify_role_holders(
        v_loan.community_id, v_target_stage.role_id, new.loan_id,
        'Loan sent back to your stage',
        v_current_stage.stage_name || ' sent ' || v_applicant_name || '''s loan back to you: ' || new.comment
      );
      perform notify_applicant(
        new.loan_id, 'Your loan was sent back a step',
        v_current_stage.stage_name || ' sent your loan back to ' || v_target_stage.stage_name || ': ' || new.comment
      );
    end if;

  elsif new.action = 'approved' then
    select max(stage_order) into v_max_stage from workflow_stages where template_id = v_loan.template_id;

    if v_loan.current_stage_order >= v_max_stage then
      update loans
        set status = 'disbursed', disbursed_at = now(),
            amount_disbursed = coalesce(amount_disbursed, amount_requested)
        where id = new.loan_id;

      perform notify_applicant(new.loan_id, 'Loan disbursed',
        'Your loan of ' || v_loan.amount_requested || ' has been disbursed.');
      perform notify_all_past_actors(new.loan_id, 'Loan disbursed',
        v_applicant_name || '''s loan has been fully approved and disbursed.');
    else
      update loans set current_stage_order = current_stage_order + 1, status = 'in_review'
        where id = new.loan_id;

      select * into v_target_stage from workflow_stages
        where template_id = v_loan.template_id and stage_order = v_loan.current_stage_order + 1;

      perform notify_role_holders(
        v_loan.community_id, v_target_stage.role_id, new.loan_id,
        'Loan awaiting your approval',
        v_applicant_name || '''s loan is now at your stage (' || v_target_stage.stage_name || ').'
      );
      perform notify_applicant(new.loan_id, 'Your loan moved forward',
        'Your loan passed ' || v_current_stage.stage_name || ' and is now at ' || v_target_stage.stage_name || '.');
    end if;
  end if;

  return new;
end;
$$;

create trigger on_stage_action_process
  after insert on loan_stage_actions
  for each row execute function process_stage_action();

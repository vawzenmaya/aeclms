-- ============================================================
-- LOAN MANAGEMENT SYSTEM — CORE SCHEMA
-- Run this in Supabase Dashboard → SQL Editor → New query
-- ============================================================

-- ---------- Extensions ----------
create extension if not exists "uuid-ossp";

-- ============================================================
-- 1. COMMUNITIES
-- ============================================================
create table communities (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now()
);

-- ============================================================
-- 2. PROFILES (extends auth.users)
-- ============================================================
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  community_id uuid references communities(id),
  full_name text not null,
  phone text,
  avatar_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ============================================================
-- 3. ROLES (reference table — not per-user, just the catalog)
-- ============================================================
create table roles (
  id smallint primary key,
  code text unique not null,   -- machine-readable
  label text not null          -- human-readable
);

insert into roles (id, code, label) values
  (1, 'member', 'Member'),
  (2, 'loan_officer', 'Loan Officer'),
  (3, 'loan_reviewer', 'Loan Reviewer'),
  (4, 'committee_chairperson', 'Loan Committee Chairperson'),
  (5, 'general_secretary', 'General Secretary'),
  (6, 'treasurer', 'Treasurer'),
  (7, 'community_chairperson', 'Community Chairperson'),
  (8, 'auditor', 'Auditor'),
  (9, 'ex_officio', 'Ex-Officio');

-- ============================================================
-- 4. USER_ROLES (who holds what role, in which community)
--    A person can hold multiple roles; roles are scoped to a community
-- ============================================================
create table user_roles (
  id uuid primary key default uuid_generate_v4(),
  profile_id uuid not null references profiles(id) on delete cascade,
  role_id smallint not null references roles(id),
  community_id uuid not null references communities(id),
  is_active boolean not null default true,
  assigned_at timestamptz not null default now(),
  unique (profile_id, role_id, community_id)
);

-- ============================================================
-- 5. WORKFLOW TEMPLATES & STAGES
--    Defines the ORDER of approval for a loan type.
--    Treasurer appears twice (review, then disbursement) — that's fine,
--    each row is just a distinct stage pointing at the same role.
-- ============================================================
create table workflow_templates (
  id uuid primary key default uuid_generate_v4(),
  loan_type text not null check (loan_type in ('new', 'topup')),
  name text not null,
  is_active boolean not null default true
);

create table workflow_stages (
  id uuid primary key default uuid_generate_v4(),
  template_id uuid not null references workflow_templates(id) on delete cascade,
  stage_order int not null,
  role_id smallint not null references roles(id),
  stage_name text not null,       -- e.g. "Treasurer Review" vs "Treasurer Disbursement"
  is_disbursement_stage boolean not null default false,
  unique (template_id, stage_order)
);

-- Seed one workflow template used for both new + topup loans (identical flow for now)
insert into workflow_templates (id, loan_type, name) values
  ('00000000-0000-0000-0000-000000000001', 'new',   'Standard New Loan Workflow'),
  ('00000000-0000-0000-0000-000000000002', 'topup', 'Standard Top-up Loan Workflow');

insert into workflow_stages (template_id, stage_order, role_id, stage_name, is_disbursement_stage)
select t.id, s.stage_order, s.role_id, s.stage_name, s.is_disbursement_stage
from (values
  (1, 2, 'Loan Officer Review', false),
  (2, 3, 'Loan Reviewer Review', false),
  (3, 4, 'Committee Chairperson Approval', false),
  (4, 5, 'General Secretary Approval', false),
  (5, 6, 'Treasurer Review', false),
  (6, 7, 'Community Chairperson Approval', false),
  (7, 8, 'Auditor Approval', false),
  (8, 9, 'Ex-Officio Approval', false),
  (9, 6, 'Treasurer Disbursement', true)
) as s(stage_order, role_id, stage_name, is_disbursement_stage)
cross join workflow_templates t;
-- (this inserts the same 9 stages for BOTH templates above; fine since flow is identical)

-- ============================================================
-- 6. LOANS
-- ============================================================
create table loans (
  id uuid primary key default uuid_generate_v4(),
  applicant_id uuid not null references profiles(id),
  community_id uuid not null references communities(id),
  template_id uuid not null references workflow_templates(id),
  loan_type text not null check (loan_type in ('new', 'topup')),
  amount_requested numeric(14,2) not null,
  amount_disbursed numeric(14,2),
  purpose text,
  status text not null default 'submitted'
    check (status in ('draft','submitted','in_review','returned','rejected','approved','disbursed')),
  current_stage_order int not null default 1,
  submitted_at timestamptz,
  disbursed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 7. LOAN DOCUMENTS (uploaded forms/files — stored in Supabase Storage)
-- ============================================================
create table loan_documents (
  id uuid primary key default uuid_generate_v4(),
  loan_id uuid not null references loans(id) on delete cascade,
  doc_type text not null,          -- e.g. 'application_form', 'id_copy', 'payslip'
  storage_path text not null,      -- path inside the storage bucket
  uploaded_by uuid not null references profiles(id),
  uploaded_at timestamptz not null default now()
);

-- ============================================================
-- 8. LOAN STAGE ACTIONS (the audit trail of approvals/rejections)
-- ============================================================
create table loan_stage_actions (
  id uuid primary key default uuid_generate_v4(),
  loan_id uuid not null references loans(id) on delete cascade,
  stage_id uuid not null references workflow_stages(id),
  actor_id uuid not null references profiles(id),
  action text not null check (action in ('approved','rejected','returned')),
  comment text,
  acted_at timestamptz not null default now()
);

-- ============================================================
-- 9. NOTIFICATIONS
-- ============================================================
create table notifications (
  id uuid primary key default uuid_generate_v4(),
  recipient_id uuid not null references profiles(id) on delete cascade,
  loan_id uuid references loans(id) on delete cascade,
  title text not null,
  body text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

-- ============================================================
-- Helpful indexes
-- ============================================================
create index idx_loans_applicant on loans(applicant_id);
create index idx_loans_status on loans(status);
create index idx_user_roles_profile on user_roles(profile_id);
create index idx_notifications_recipient on notifications(recipient_id, is_read);
create index idx_stage_actions_loan on loan_stage_actions(loan_id);

# AECLMS — Complete System Documentation (AI Agent Handoff)

This document is the single source of truth for the AEC Loan Management System.
It is written so that another AI coding agent (or a new human developer) can pick
up this project with zero prior context and understand: what this system is,
exactly what has been built, exactly what hasn't, what is known to be broken or
incomplete, and what to do next. Read this fully before changing anything.

---

## 1. What this system is

**AECLMS** is a community loan management and tracking system for a real
organization (referred to internally as "AEC"). Members of the community lend
to and borrow from each other. **No real money moves through this system** —
actual disbursement and repayment happen outside it (bank RTGS transfer, and a
payroll deduction system respectively). This app's job is to:

- Take structured loan applications
- Route them through a strict multi-person approval chain so no single person
  can unilaterally approve their own or anyone else's loan
- Track and display status to everyone involved
- Calculate interest/repayment correctly (mirroring a known-good Excel model)
- Record (not execute) the automatic monthly payroll deduction, reducing an
  outstanding balance over time for reporting purposes
- Eventually produce reports (not built yet)

The person building this (the user) is a solo, non-technical-background founder
with Django/Render experience but is new to Supabase and Flutter. They have
community approval to build this and a real, current need for actual members to
use it soon. **Correctness and clarity matter more than elegance.**

---

## 2. Tech stack

- **Frontend:** Flutter (package name: `aeclms`). Material 3, green color seed,
  full light + dark theme from day one.
- **Backend:** Supabase — Postgres, Auth, Storage, `pg_cron` for scheduled jobs.
  Almost all business logic lives in the database as SQL functions/triggers,
  not in Dart — this means rules can't be bypassed by a buggy screen.
- **State management:** currently plain `StatefulWidget` + direct Supabase
  calls via repository classes. No Riverpod/Bloc in use yet despite being in
  `pubspec.yaml` (added preemptively, not yet needed).
- **Auth:** Supabase email/password auth. `Confirm email` is currently
  **disabled** for faster dev testing — must be re-enabled before real
  production use.

---

## 3. Current status — what works, what doesn't, what needs to change

### Fully working and tested
- Sign up / log in / log out
- Auth gate routing: no session -> login; session but no community assigned ->
  pending screen; fully set up -> dashboard
- Full 9-stage sequential approval workflow (see section 6)
- Reject-to-previous-stage logic with mandatory comment
- Guarantor digital confirm/decline gate
- PMT (reducing balance) and flat-interest repayment calculation, matching a
  verified Excel model
- Debt-to-income ratio calculated and flagged (never blocks submission)
- Loan category rules: Emergency (4% flat, <=2 months, no top-ups) vs Normal
  (reducing balance, <=60 months, top-ups allowed)
- Application form: every field from the paper form, live repayment preview,
  save-as-draft and submit
- Loans dashboard: "Awaiting your action" / "My applications" / "History"
- Loan detail screen: stage tracker, Approve/Reject with comment, guarantor
  Confirm/Decline, disbursement date capture on final approval
- Automatic notifications written by DB triggers (see 6.5) — data layer only
- Daily automatic repayment deduction job (`pg_cron`)
- Amortization schedule generation on disbursement
- Notifications screen (bell icon + badge, mark read, tap-through to the
  related loan)
- Document upload: Storage RLS policies on `storage.objects` for the
  `loan-documents` bucket, plus a full upload/list/view UI. Now lives on a
  **standalone, mandatory screen** (`document_upload_screen.dart`) between
  saving an application and reaching the tracking screen — not embedded in
  the detail screen as an optional afterthought (that was tried first and
  correctly rejected as confusing).
- Draft continuation flow: saving a draft always routes to the Documents
  screen next (never straight to tracking); "Edit"/"Documents & Submit" on
  the detail screen route back through the same chain for resubmissions.
- **UI redesign (user-authored, not this assistant):** the application form
  is now a proper 6-step wizard with a progress bar and animated
  transitions; the loan detail screen has a hero amount display, a metrics
  grid (interest/fee/installment/DTI), a details card, and an animated
  vertical stage timeline. Preserve this styling when making further changes
  — don't revert to the earlier plainer versions.

### Backend exists, no UI yet
- **Reports** — not designed at all yet, deliberately deferred.

### Not built at all
- Admin UI for assigning `community_id` / roles to new members — currently
  done manually via Supabase Table Editor (`profiles.community_id` and
  `user_roles` table). This does not scale past a handful of members but is
  acceptable short-term.
- Push notifications (only in-app `notifications` table rows exist; no FCM/APNs
  wiring).
- Any visual design pass — the UI is functional, plain Material 3, not yet
  "polished" per the original ask for an eye-catching design.
- App icon (a piggy-bank icon was liked in conversation but never generated as
  actual launcher icon assets).

### Known bug classes already hit and fixed (READ THIS BEFORE TOUCHING RLS)
These are not hypothetical — each one actually broke the app in testing and
cost real debugging time. If you add new tables/policies, watch for these
exact patterns:

1. **Self-referencing RLS infinite recursion (Postgres error `42P17`).** A
   policy on table `X` that queries `X` again inside its own `USING` clause
   causes "infinite recursion detected in policy for relation X". Fixed by
   moving the internal lookup into a `SECURITY DEFINER` function (which
   bypasses RLS on its own internal query, since the function owner — the
   table owner — bypasses RLS by default). See `my_profile_community_id()`.

2. **Cross-table RLS recursion.** Two policies on *different* tables that each
   query the other's table can form a cycle just as fatal as #1, even if
   neither one directly self-references. Happened between `loans` and
   `loan_stage_actions`. Same fix: wrap each cross-table check in its own
   `SECURITY DEFINER` function (`has_acted_on_loan()`,
   `loan_visible_to_current_user()`).

3. **Missing `WITH CHECK` on UPDATE policies.** If you write
   `for update using (X)` with no explicit `with check`, Postgres defaults
   `WITH CHECK` to be identical to `USING` — meaning the *new* row must also
   satisfy the same condition as the *old* row. This silently blocks any
   update that's supposed to change the very column the `USING` clause
   checks (e.g. an update whose whole purpose is to change `status` away from
   `'draft'`). Always write an explicit, deliberately looser `WITH CHECK`
   when the update is meant to transition state.

4. **Tables created via the SQL Editor don't automatically get default grants**
   the way tables created through the dashboard UI do. A table with RLS
   disabled (intentionally, for shared reference data) can still be
   completely unreadable by the `authenticated` role if the base `GRANT
   SELECT` was never issued. Symptom: queries succeed (200 OK) but always
   return 0 rows for `authenticated`, while `postgres` sees everything. Fixed
   with explicit `grant select on <table> to authenticated;` plus
   `alter default privileges in schema public grant select on tables to
   authenticated;` so future tables don't repeat this.

5. **RLS silently enabled with zero policies = default-deny for everyone
   except the owner.** Same 0-rows-for-authenticated symptom as #4, different
   cause — someone (or a dashboard prompt) can flip
   `ENABLE ROW LEVEL SECURITY` on with no policy attached. Always pair
   `ENABLE ROW LEVEL SECURITY` with at least one `CREATE POLICY` in the same
   migration.

6. **A trigger referencing `OLD` during an `INSERT`.** `OLD` does not exist
   during an `INSERT` — referencing `OLD.anything` inside a trigger that's
   defined to fire on both `INSERT OR UPDATE` throws "record 'old' is not
   assigned yet" unless you branch explicitly on `TG_OP` first (don't rely on
   `OR` short-circuiting — Postgres doesn't guarantee it for general boolean
   expressions).

7. **A trigger reading a column from the wrong table.** `snapshot_guarantor_details()`
   tried to `select email from profiles` — but `email` has never existed on
   `profiles`; it only exists on Supabase's built-in `auth.users` table. Fixed
   by joining `profiles p join auth.users u on u.id = p.id` and reading
   `u.email`. Lesson: `profiles` holds app-specific data; `auth.users` holds
   Supabase's own auth fields (email, phone-for-auth, etc.) — don't assume
   they're merged.

8. **Partial script execution silently swallowed.** Pasting a very long
   multi-statement SQL script into the SQL Editor and running it as one block
   can, if an early statement errors, leave later statements unexecuted —
   with no obvious indication of exactly where it stopped. Symptom: a column
   that should exist per the source files genuinely doesn't exist in the live
   database. Mitigation adopted: all "fix" migrations now use
   `ADD COLUMN IF NOT EXISTS` and are individually re-runnable, and there is a
   diagnostic pattern of directly querying `information_schema.columns` to
   verify ground truth rather than assuming a past run succeeded.

9. **Storage RLS is a completely separate permission system from table RLS.**
   Creating a Storage bucket and a regular table (`loan_documents`) to track
   metadata about files in it does NOT grant anyone permission to actually
   upload/download from the bucket. `storage.objects` has its own RLS that
   must be configured independently, using `storage.foldername(name)` to
   parse the object path if you want per-folder permission logic (e.g. "you
   can only upload into a folder matching a loan you own").

---

## 4. Repository structure

```
loan-system/
├── START_HERE.md              — step-by-step Supabase + Flutter setup checklist
├── SYSTEM_OVERVIEW.md          — earlier architecture summary (superseded by this doc, kept for history)
├── TWO_DAY_PLAN.md             — active sprint plan / priority list
├── AI_AGENT_HANDOFF.md         — this document
├── pubspec.yaml
├── sql/
│   ├── 00_full_schema.sql      — ALL migrations concatenated, in order — the only file needed for a fresh DB
│   └── 01_...17_...sql         — individual migrations, kept as readable history (see section 5)
└── lib/
    ├── main.dart                — Supabase.initialize + MaterialApp, boots into AuthGate
    ├── core/
    │   ├── theme/app_theme.dart      — green seed color, light+dark ThemeData, StatusColors helper
    │   └── utils/amount_to_words.dart — client-side number-to-words for the "Amount in words" field
    └── features/
        ├── auth/
        │   ├── data/auth_service.dart        — Supabase auth wrapper + Profile model + fetchCurrentProfile()
        │   └── presentation/
        │       ├── auth_gate.dart            — routes: no session/pending/dashboard, surfaces real errors
        │       ├── login_screen.dart
        │       ├── signup_screen.dart
        │       └── widgets/auth_text_field.dart
        ├── home/
        │   └── presentation/home_placeholder_screen.dart  — PendingAssignmentScreen (still used) + old HomePlaceholderScreen (now unused, superseded by dashboard)
        ├── notifications/
        │   ├── data/notifications_repository.dart   — fetch all, unread count, mark read/mark all read
        │   └── presentation/notifications_screen.dart
        ├── documents/
        │   ├── data/documents_repository.dart        — upload/list/signed-URL/delete against the loan-documents bucket
        │   └── presentation/
        │       ├── documents_section.dart      — embedded upload/list widget, reused in two places
        │       └── document_upload_screen.dart  — standalone mandatory step between saving a draft and tracking it
        └── loans/
            ├── data/loan_repository.dart      — ALL Supabase calls for loans live here (see section 7)
            ├── domain/loan_calculations.dart  — Dart mirror of calc_pmt/calc_flat_installment, for live preview only
            └── presentation/
                ├── application_form_screen.dart   — 6-step wizard (Classification, Personal, Loan Details, Security/Guarantor, Bank, Review) with a step progress bar and animated transitions
                ├── loans_dashboard_screen.dart     — home screen: 3 sections + FAB to apply
                ├── loan_detail_screen.dart         — rich tracking screen: hero amount, metrics grid, details card, embedded documents, animated stage timeline, docked action bar
                └── widgets/
                    ├── loan_status_chip.dart
                    └── repayment_preview_card.dart
```

Note: `core/widgets/custom_loader.dart` is a small custom loading-spinner
widget the user built independently; a same-signature placeholder is included
so the package compiles standalone, but keep the user's real one if it
already exists in the actual project.

Not yet created (needs building): any `lib/features/admin/` (role/community assignment UI).

---

## 5. Database migrations — what each file did, in order

Run `sql/00_full_schema.sql` once for a fresh database (it's the concatenation
of everything below, in order). The individual files remain for history/audit.

| File | Purpose |
|---|---|
| `01_schema.sql` | Core schema: `communities`, `profiles`, `roles`, `user_roles`, `workflow_templates`, `workflow_stages` (9 stages seeded for both `new` and `topup` templates), `loans`, `loan_documents`, `loan_stage_actions`, `loan_settings`, `loan_amortization_schedule`, `repayments`, `notifications`. |
| `02_security_and_triggers.sql` | Enables RLS on the per-user tables. `has_role()` and `is_current_stage_approver()` bypass functions. Auto-create-profile-on-signup trigger. `updated_at` trigger. First version of the approve/reject processor (`process_stage_action`), terminal-reject only (later replaced). |
| `03_reject_flow_and_notifications.sql` | Changes reject from terminal to "send back one stage" (or to applicant if stage 1). Mandatory comment on reject enforced by a CHECK constraint. Adds draft status + `parent_loan_id` for top-ups. Real notification triggers via `notify_role_holders/notify_applicant/notify_all_past_actors`. |
| `04_repayments.sql` | Adds `installment_amount`, `next_deduction_date`, `outstanding_balance` to `loans`; disbursement now requires these from the Treasurer. `repayments` table + RLS. Daily `pg_cron` job (`run_daily_repayment_deductions`) that auto-deducts and marks `completed` at zero balance. |
| `05_repayment_calculation.sql` | Replaces manual installment entry with a real PMT formula (`calc_pmt`). Adds `net_pay`, `term_months`, `interest_rate`, `processing_fee`, `debt_to_income_ratio`. At this point DTI over 20% was a hard submission block (later changed, see file 06). Adds `generate_amortization_schedule()`. |
| `06_application_form_fields.sql` | Every remaining paper-form field: `category`, `employee_number`, snapshot `full_name/email/phone`, `amount_in_words`, security fields, guarantor text fields (pre-digital-guarantor), full RTGS bank fields + `bank_details_confirmed`. Changes DTI from a hard block to a flag (`dti_exceeded` column) — the committee decides, per explicit user instruction. |
| `07_guarantor_confirmation.sql` | Guarantor becomes a real `profiles` reference (`guarantor_id`), not free text. New status `awaiting_guarantor` sits before the committee. `guarantor_respond()` RPC function is the only way to confirm/decline (never a raw table update) so nobody but the assigned guarantor can act on it. |
| `08_loan_categories.sql` | Adds `loan_category` (`emergency`/`normal`), independent of `loan_type` (`new`/`topup`). Emergency = 4% flat one-time interest, <=2 months, top-ups disallowed for emergency (`topup_only_for_normal` constraint). Normal = existing reducing-balance PMT, <=60 months. `calc_flat_installment()` added. Amortization generator branches by category. |
| `09_profile_self_view_fix.sql` | Bug fix: users couldn't see their own profile before a community was assigned, because `NULL = NULL` is not true in SQL. Adds an unconditional "view own profile" policy. |
| `10_fix_profiles_recursion.sql` | Bug fix: see gotcha #1 above. `my_profile_community_id()` bypass function. |
| `11_fix_applicant_submit_check.sql` | Bug fix: see gotcha #3 above, on the `loans` applicant-edit policy. |
| `12_fix_guarantor_trigger_on_insert.sql` | Bug fix: see gotcha #6 above, in `snapshot_guarantor_details()`. |
| `13_fix_missing_grants.sql` | Bug fix: see gotcha #4 above, for `workflow_templates`, `workflow_stages`, `roles`, `communities`, `loan_settings`. |
| `14_fix_reference_table_rls.sql` | Bug fix: see gotcha #5 above — same tables as #13 turned out to also have RLS on with zero policies; added explicit "readable by authenticated" policies. |
| `15_fix_loans_stage_actions_recursion.sql` | Bug fix: see gotcha #2 above, between `loans` and `loan_stage_actions`. |
| `16_ensure_loan_columns.sql` | Bug fix: see gotcha #8 above — idempotent catch-up re-adding every `loans`/`loan_stage_actions` column with `IF NOT EXISTS`, re-attaching CHECK constraints defensively. |
| `17_fix_guarantor_email_reference.sql` | Bug fix: see gotcha #7 above, corrected version of `snapshot_guarantor_details()` joining `auth.users` for email. |
| `18_storage_policies.sql` | Storage RLS on `storage.objects` for the `loan-documents` bucket — see gotcha #9. Applicant can upload into their own loan's folder; anyone who can see the loan (applicant, current-stage approver, guarantor) can view its documents; applicant can delete while the loan is still draft/returned. |
| `19_require_document_before_submit.sql` | Adds a hard requirement (in `handle_loan_submission()`) that at least one row must exist in `loan_documents` for a loan before it can be submitted. Prompted the removal of the direct "Submit" button from the application form, since a new loan has no id to attach documents to until saved once — see section 6.7. |

If you are an AI agent continuing this project: treat `00_full_schema.sql`
as authoritative, but when in doubt about the actual live state of a
database that's already been through several of these runs, query
`information_schema.columns` / `pg_policies` directly rather than assuming —
see gotcha #8.

---

## 6. Business rules — the actual domain logic

### 6.1 Roles
`member`, `loan_officer`, `loan_reviewer`, `committee_chairperson`,
`general_secretary`, `treasurer`, `community_chairperson`, `auditor`,
`ex_officio`. A person can hold multiple roles (`user_roles`, scoped per
community) and can also apply for loans themselves, including approving their
own application at a stage they hold — this is allowed by explicit design;
the multi-person chain is the safeguard, not self-recusal.

### 6.2 The approval workflow — strictly sequential, same order for every loan
1. Loan Officer Review
2. Loan Reviewer Review
3. Committee Chairperson Approval
4. General Secretary Approval
5. Treasurer Review
6. Community Chairperson Approval
7. Auditor Approval
8. Ex-Officio Approval
9. Treasurer Disbursement (final — actually disburses, requires a
   `first_deduction_date`)

`loans.current_stage_order` + `workflow_stages` (joined on `template_id` +
`stage_order`) tells you exactly where a loan is and whose job it is next.

### 6.3 Loan lifecycle (`loans.status`)
```
draft --(submit, no guarantor)------------------------> in_review
  |
  +--(submit, guarantor set)--> awaiting_guarantor
                                     |
                         (guarantor confirms) --> in_review
                                     |
                         (guarantor declines) --> returned_to_applicant --> (edit, resubmit) --> draft flow again

in_review --(reject at stage 1)-----------> returned_to_applicant
in_review --(reject at stage > 1)---------> back one stage, stays in_review
in_review --(approve, not final stage)----> next stage, stays in_review
in_review --(approve, final stage)--------> disbursed
disbursed --(balance reaches 0 via daily job)--> completed
```
`rejected` also exists as a status value but is not currently used by any
trigger path (kept for a possible future "hard stop" scenario, e.g. fraud).

### 6.4 Two independent loan classifications
- `loan_type`: `new` or `topup`. Top-ups only valid when `loan_category = 'normal'`
  (enforced by a CHECK constraint).
- `loan_category`: `emergency` or `normal`.
  - Emergency: 4% flat one-time interest (not annualized), <=2 months, no
    top-ups.
  - Normal: reducing-balance PMT at the community's configured annual rate
    (`loan_settings.annual_interest_rate`), <=60 months (5 years).
  - Both use the identical 9-stage approval chain.

### 6.5 Notifications (data layer complete, no UI)
Triggers automatically insert rows into `notifications` for: new submission
(to stage-1 approver), guarantor requested/confirmed/declined, every
approve/reject transition (to the relevant next/previous approver and the
applicant), disbursement (to applicant + everyone who ever acted on the loan),
each automatic repayment deduction, and full repayment completion. Building
the screen that reads this table is the top priority next task.

### 6.6 Repayment engine
- Normal: `calc_pmt(principal, annual_rate_pct, term_months)` — standard
  reducing-balance formula, mirrors `=-PMT(rate/12, nper, principal, 0, 0)`.
- Emergency: `calc_flat_installment(principal, flat_rate_pct, term_months)` =
  `(principal + principal x rate%) / term_months`.
- `processing_fee` = 0.5% of amount requested, same for every loan
  (`loan_settings.processing_fee_rate`).
- `debt_to_income_ratio` = installment / net_pay. Flagged (`dti_exceeded`) if
  over `loan_settings.max_debt_to_income_ratio` (default 20%) — never blocks
  submission, purely informational for the committee.
- On disbursement: `generate_amortization_schedule()` builds the full
  period-by-period table in `loan_amortization_schedule` (installment /
  interest / principal / balance), branching its math by `loan_category`.
- Daily `pg_cron` job auto-deducts the installment from `outstanding_balance`
  on/after `next_deduction_date`, logs a `repayments` row, advances the date a
  month, and marks the loan `completed` at zero balance.

### 6.7 Application form to database field mapping
See `SYSTEM_OVERVIEW.md` section 7 for the full paper-form-to-column mapping
table if needed; it has not changed since originally written. Everything is
captured except that guarantor confirmation is now digital (6.8) rather than
a signature line.

**Required before a loan can be submitted:** net pay, term, complete
confirmed bank details, and **at least one uploaded document** (enforced in
`handle_loan_submission()` — a submission with zero rows in `loan_documents`
for that loan is rejected). Everything else follows the paper form as-is.

**Current flow (post-redesign):** the applicant fills a 6-step wizard
(`application_form_screen.dart`) covering Classification, Personal details,
Loan details, Security/Guarantor, Bank details, and a final Review step. The
wizard's only action is **save** (there is no direct submit button on the
form) — saving always navigates to the standalone
`document_upload_screen.dart`, which is a mandatory intermediate step: upload
at least one document, then **Submit** from that screen (which is where the
actual `submit()` call and its document-count check both live). Only after
that does the user land on `loan_detail_screen.dart` for ongoing tracking.
`loan_detail_screen.dart` also embeds the same documents widget (read-only
once submitted, editable again if the loan is `draft`/`returned_to_applicant`)
and its own "Edit"/"Documents & Submit" actions route back through the same
form → documents → detail chain for resubmissions.

Every hand-off in this chain uses `Navigator.pushReplacement`, not `push`, so
the stack never accumulates stale copies of the form or a previous version of
the detail screen — each step cleanly replaces the last.

### 6.8 Guarantor flow
Guarantor must be an actual community member selected from a picker (not free
text). They act only via the `guarantor_respond(loan_id, confirm, comment)`
RPC — never a direct table write — so only the assigned guarantor can ever
confirm/decline on their own behalf. Declining requires a reason and returns
the loan to the applicant.

### 6.9 Loan settings (per-community, tunable)
`loan_settings` table: `annual_interest_rate`, `processing_fee_rate`,
`max_debt_to_income_ratio`, `emergency_flat_interest_rate`,
`emergency_max_term_months`, `normal_max_term_months`. Must be seeded once per
community — there is currently no UI for this, done via SQL insert.

---

## 7. Flutter data layer — LoanRepository method reference

All Supabase calls for loans go through `lib/features/loans/data/loan_repository.dart`:

- `fetchLoanSettings(communityId)` -> `LoanSettings` (falls back to sane
  defaults if unseeded)
- `fetchPossibleGuarantors(communityId, excludeProfileId)` -> list for the
  guarantor picker
- `saveDraft(...)` -> creates or updates a loan row (insert if
  `existingLoanId` null, else update); throws a specific `Exception` (not
  swallowed) if the workflow template lookup or the insert/update-with-return
  comes back empty, naming exactly which step failed
- `submit(loanId, hasGuarantor)` -> flips status to `awaiting_guarantor` or
  `in_review`; the DB trigger does the rest
- `fetchLoan(loanId)`, `fetchVisibleLoans()` (RLS-filtered "everything I'm
  allowed to see")
- `fetchMyStageAssignments(profileId, communityId)` -> set of
  `"templateId:stageOrder"` strings representing every stage any role I hold
  is responsible for — used client-side to work out if an `in_review` loan is
  actually awaiting my action right now
- `fetchCurrentStage(loan)`, `fetchAllStages(templateId)` -> for the stage
  tracker UI
- `respondAsGuarantor(loanId, confirm, comment)` -> wraps the `guarantor_respond` RPC
- `recordStageAction(loanId, stageId, actorId, action, comment,
  firstDeductionDate)` -> inserts into `loan_stage_actions`; the DB trigger
  advances/reverts/disburses automatically

`LoanCalculations` (domain layer) is a pure-Dart mirror of the SQL PMT/flat
formulas, used only for the live preview in the application form before
saving — the database is always the authoritative calculation on save.

---

## 8. Immediate next steps (priority order)

1. **End-to-end multi-account test** across the full 9-stage chain with real
   or realistic test accounts, including at least one reject-and-resend cycle,
   one guarantor decline + resubmit, and one full disbursement with document
   uploads attached.
2. **Visual polish pass** — once the above is confirmed working, not before.
3. **Admin convenience** — at minimum, keep documenting the exact Table
   Editor steps (already in `START_HERE.md`) for assigning new members; a
   real admin screen is a stretch goal, not a blocker.
4. **Reports** — not scoped yet at all; needs a requirements conversation
   before any building starts.

---

## 9. Setup (condensed — see START_HERE.md for the full walkthrough)

1. Fresh Supabase project -> SQL Editor -> run `sql/00_full_schema.sql` once.
2. Enable Email auth provider; disable "Confirm email" for dev.
3. Create a private Storage bucket `loan-documents` (PDF/JPEG/PNG only).
4. Copy Project URL + Publishable key (`sb_publishable_...` — this is the
   modern name for the "anon key") into `lib/main.dart`. Never use the
   Secret key (`sb_secret_...`, the modern "service_role") in the app.
5. Insert one `communities` row, then one `loan_settings` row referencing it.
6. `flutter pub get`, run the app, sign up, then manually set
   `profiles.community_id` and add a `user_roles` row for your test account
   via Table Editor.
7. Repeat for a second test account with a different role to test the
   approval chain end-to-end.

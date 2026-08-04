# System Overview — AEC Loan Management System

This is the reference doc for everything we've designed so far. Read this when you
forget why something works the way it does — it's the map of the whole system.

---

## 1. The big picture

- **Backend:** Supabase (Postgres + Auth + Storage + scheduled jobs). Almost all the
  business logic (workflow, notifications, repayment math) lives in the database as
  triggers/functions — not in the Flutter app. This means the rules can't be bypassed
  by a buggy screen or a clever user; Postgres enforces them no matter what.
- **Frontend:** Flutter, green theme, dark mode from day one.
- **No real money moves through the system.** It mirrors what happens elsewhere
  (payroll deduction) and tracks it for reporting.

## 2. Roles (`roles` table)

| Code | Label |
|---|---|
| `member` | Member |
| `loan_officer` | Loan Officer |
| `loan_reviewer` | Loan Reviewer |
| `committee_chairperson` | Loan Committee Chairperson |
| `general_secretary` | General Secretary |
| `treasurer` | Treasurer |
| `community_chairperson` | Community Chairperson |
| `auditor` | Auditor |
| `ex_officio` | Ex-Officio |

A person can hold multiple roles (`user_roles`), and **anyone can also apply for a
loan themselves** — including approvers reviewing their own case. That's fine by
design: the multi-person chain is the safeguard, not self-recusal.

## 3. The approval workflow (`workflow_stages`)

Strictly sequential, one person at a time, same order for new loans and top-ups:

1. Loan Officer Review
2. Loan Reviewer Review
3. Committee Chairperson Approval
4. General Secretary Approval
5. Treasurer Review
6. Community Chairperson Approval
7. Auditor Approval
8. Ex-Officio Approval
9. **Treasurer Disbursement** ← final stage, triggers actual disbursement

A loan's `current_stage_order` says exactly where it is; `workflow_stages` +
`roles` tells you whose job that is. This is what powers the applicant's tracker.

## 4. Loan lifecycle (`loans.status`)

```
draft ──(submit)──► awaiting_guarantor ──(guarantor confirms)──► in_review
  ▲                        │                                        │
  │                   (guarantor declines)                    (approve × 9)
  │                        │                                        ▼
  └───── returned_to_applicant ◄──(reject at stage 1)──────────  disbursed
                            ▲                                        │
                            └──(reject at stage > 1: back one stage)  │
                                                                       ▼
                                                                  completed
                                                            (balance reaches 0)
```

- If no guarantor is attached (guarantor is "where necessary"), submission skips
  straight from `draft` to `in_review`.
- **Reject** always sends the loan back one stage — to the previous approver, or to
  the applicant if rejected at stage 1. A comment/reason is mandatory on every reject.
- **Approve** at any non-final stage moves it forward one stage. Approve at the final
  stage (Treasurer Disbursement) actually disburses it — this requires a
  `first_deduction_date` to be supplied.

## 5. Notifications

Fired automatically by triggers — nothing in Flutter needs to remember to send one:

- New submission → notifies the Loan Officer
- Guarantor requested → notifies the guarantor
- Guarantor confirms → notifies the Loan Officer + the applicant
- Guarantor declines → notifies the applicant (with the reason)
- Any approval → notifies the next-stage approver + the applicant
- Any rejection → notifies the previous-stage approver (or applicant) + the applicant
- Disbursement → notifies the applicant + everyone who ever acted on the loan
- Each automatic repayment deduction → notifies the applicant
- Loan fully repaid → notifies the applicant

## 6. Loan categories: Emergency vs Normal

Every loan is also classified by `loans.loan_category`, independent of `loan_type`
(new/topup):

| | Emergency | Normal |
|---|---|---|
| Interest | **4% flat**, one-time charge on the principal — not annualized, not reducing balance | Annual rate on **reducing balance** (PMT), from `loan_settings.annual_interest_rate` |
| Max term | **2 months** (`loan_settings.emergency_max_term_months`) | **60 months / 5 years** (`loan_settings.normal_max_term_months`) |
| Top-ups | **Not allowed** — `loan_type = 'topup'` is only valid when `loan_category = 'normal'` | Allowed |
| Approval chain | Same full 9-stage chain as any other loan | Same full 9-stage chain |

The database **rejects** (raises an error) any loan whose `term_months` exceeds the
limit for its category — this can't be bypassed from the app.

`interest_method` is set automatically: `'flat'` for Emergency, `'reducing_balance'`
for Normal. The amortization schedule generator (`generate_amortization_schedule`)
branches on this — Emergency schedules show the same flat interest portion every
period; Normal schedules show interest shrinking as the balance reduces, same as
before.

## 7. Repayment (`loan_settings`, PMT calculation)

Mirrors your spreadsheet's reducing-balance method for **Normal** loans, and a
simple flat calculation for **Emergency** loans:

- **Normal:** `installment_amount` = PMT(rate/12, term_months, amount_requested) —
  calculated automatically, never entered by hand.
- **Emergency:** `installment_amount` = (principal + principal × 4%) ÷ term_months —
  the 4% is charged once on the whole loan, then split evenly across the (short)
  repayment period.
- `processing_fee` = 0.5% of the amount requested, same formula for every loan
  regardless of category (`loan_settings.processing_fee_rate`).
- `interest_rate` and `interest_method` are **snapshots** taken at application time,
  so changing community settings later doesn't rewrite history on old loans.
- `debt_to_income_ratio` = installment ÷ net pay. If it exceeds 20%
  (`loan_settings.max_debt_to_income_ratio`), `dti_exceeded` is set `true` — **this is
  a flag only, never a submission blocker.** The committee sees it and decides.
- On disbursement, `generate_amortization_schedule()` builds the full month-by-month
  table (`loan_amortization_schedule`) — installment / interest / principal / balance
  per period, matching your Excel sheet's layout for Normal loans, and a flat
  equivalent for Emergency loans.
- A daily job (`pg_cron` → `run_daily_repayment_deductions()`) automatically deducts
  the installment on/after each due date, logs it in `repayments`, and marks the loan
  `completed` once the balance hits zero. This works identically for both categories
  since it only cares about `installment_amount` and `outstanding_balance`.

## 8. The application form — field-by-field mapping

| Paper form field | Database column(s) |
|---|---|
| Applicant's name / email / phone | `loans.full_name/email/phone` (snapshot) |
| Employee Number (AEC/…) | `loans.employee_number` — auto-filled from `profiles.employee_number` for members, typed for non-members |
| Amount applied for | `loans.amount_requested` |
| Amount in words | `loans.amount_in_words` — auto-filled client-side (`amount_to_words.dart`), editable |
| Application date | `loans.application_date` |
| Purpose of the loan | `loans.purpose` |
| Category (Member/Non-Member) | `loans.category` |
| Security's name and estimated value | `loans.security_description`, `loans.security_estimated_value` |
| Interest on loan / Interest method | `loans.interest_rate`, `loans.interest_method` (always `reducing_balance`) |
| Loan duration (months) | `loans.term_months` — derived from `loans.expected_end_date` |
| Total loan value | `loans.amount_requested` |
| Total monthly repayment | `loans.installment_amount` |
| Guarantor's name / signature / date | `loans.guarantor_id` (real member), digitally confirmed — see below |
| Bank details for RTGS (all fields) | `loans.bank_account_holder_name`, `bank_name`, `bank_account_number`, `bank_sort_code`, `bank_swift_code`, `bank_details_confirmed` |

**Required before a loan can be submitted:** net pay, term, and complete confirmed
bank details. Everything else follows the paper form as-is.

## 9. Guarantor confirmation

- Guarantor must be an actual community member (`profiles`), chosen from a picker —
  not free text.
- They respond only through the `guarantor_respond(loan_id, confirm, comment)`
  database function — never a direct table edit — so nobody but the assigned
  guarantor can ever confirm on their behalf.
- Decline requires a reason and sends the loan back to the applicant to pick someone
  else.

## 10. Tables at a glance

`communities` · `profiles` · `roles` · `user_roles` · `workflow_templates` ·
`workflow_stages` · `loans` · `loan_documents` · `loan_stage_actions` ·
`loan_settings` (now also holds emergency-loan rate/term rules) ·
`loan_amortization_schedule` · `repayments` · `notifications`

## 11. Still open (revisit when you're ready, not blocking)

- Reports (structure not yet designed — you said we'd look at this later)
- Whether to eventually let admins manage roles/employee numbers from within the app
  itself, rather than via the Supabase Table Editor

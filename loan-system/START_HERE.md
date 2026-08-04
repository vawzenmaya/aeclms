# START HERE — Getting Set Up

Everything below is written for someone who knows Django/Render and is new to
Supabase. Follow it top to bottom in order.

## ✅ Checklist

- [ ] Step 1 — Run the database setup
- [ ] Step 2 — Turn on Auth
- [ ] Step 3 — Create the Storage bucket
- [ ] Step 4 — Copy your API keys
- [ ] Step 5 — Seed your community + loan settings
- [ ] Step 6 — Create the Flutter project
- [ ] Step 7 — Wire up `main.dart`
- [ ] Step 8 — Create yourself a test user with a role

---

### Step 1 — Run the database setup

Open your Supabase project → **SQL Editor** → New query.

Paste in the entire contents of **`sql/00_full_schema.sql`** and hit Run.
That's it — one file, one click, and every table, security rule, trigger, and the
repayment engine are live. (The `sql/01`–`08` files are kept purely as a readable
history of how we got here — you never need to run them individually.)

> **Already ran this before and just came back for an update?** You don't need to
> re-run the whole thing — that would error on tables that already exist. Just run
> the newest numbered file you haven't applied yet (e.g. `sql/08_loan_categories.sql`)
> on its own. Each numbered file is a self-contained migration.

If anything errors on `create extension pg_cron;`, go to
**Database → Extensions**, search "pg_cron", toggle it on, then re-run just the
`cron.schedule(...)` block near the bottom of the file.

### Step 2 — Turn on Auth

**Authentication → Providers** → enable **Email**.

**Authentication → Settings** → turn off "Confirm email" while you're developing
(turn it back on before real members use it), so you're not stuck waiting on
confirmation emails while testing.

### Step 3 — Create the Storage bucket

**Storage** → **New bucket** → name it `loan-documents` → keep it **private**.
This is where uploaded forms/IDs/payslips will live.

### Step 4 — Copy your API keys

**Project Settings → API** → copy:
- **Project URL**
- **anon public key**

You'll paste these into the Flutter app in Step 7. Never use the `service_role` key
in the app — that one is server-side only.

### Step 5 — Seed your community + loan settings

In the **Table Editor**, open `communities` and add one row for your community
(e.g. "AEC Staff Investment Club"). Copy its generated `id`.

Then back in **SQL Editor**, run (with your real values):

```sql
insert into loan_settings (community_id, annual_interest_rate, processing_fee_rate, max_debt_to_income_ratio)
values ('YOUR-COMMUNITY-UUID', 10.0, 0.005, 0.20);
```

### Step 6 — Create the Flutter project

```bash
flutter create loan_management_system
cd loan_management_system
```

Replace the generated `pubspec.yaml` with the one in this folder, then:

```bash
flutter pub get
```

Copy the whole `lib/core` folder from this package into your project's `lib/core`.

### Step 7 — Wire up `main.dart`

Copy `lib/main.dart` from this package into your project, and fill in your Project
URL and anon key from Step 4.

```bash
flutter run
```

You should see the themed placeholder home screen, green palette, matching your
system's light/dark mode.

### Step 8 — Create yourself a test user with a role

1. Sign up once through the app (or **Authentication → Users → Add user** in the
   dashboard) — this auto-creates your `profiles` row via a trigger.
2. In **Table Editor → profiles**, set your `community_id` to the community from
   Step 5, and give yourself an `employee_number` (e.g. `AEC/00001`) if you're a
   member.
3. In **Table Editor → user_roles**, add a row giving yourself a role (e.g.
   `loan_officer`) for that community, so you have something to test approvals with.

---

## What to read next

Open **`SYSTEM_OVERVIEW.md`** — it's the map of everything we've built: the
workflow order, every status a loan can be in, how notifications fire, how
repayment is calculated, and the full field-by-field mapping of your paper
application form to the database. Refer back to it any time something feels
unclear while you're building screens.

## Suggested build order (screens)

1. **Auth** — sign up / login
2. **Application form** — the big one; every field is already in `SYSTEM_OVERVIEW.md` §7
3. **My Loans** (applicant's tracker) — reads `loans.current_stage_order` + `workflow_stages`
4. **Guarantor inbox** — confirm/decline requests via `guarantor_respond()`
5. **Approvals inbox** — one per role, shows loans currently at their stage
6. **Disbursement screen** — Treasurer's final step, captures `first_deduction_date`
7. **Notifications** — a simple list backed by the `notifications` table
8. **Reports** — later, once the core flow works end-to-end

Tell me which one you want to start building and we'll go screen by screen.

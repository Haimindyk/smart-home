# Deployed source recovery — 2026-11-03

The GitHub main branch was behind the running application: Wellness and several
household updates had been uploaded directly to Vercel. This recovery brings
the running source back under version control.

## What was recovered

- All 197 files from Vercel production deployment
  `dpl_Ca1pyhNkbN46fY2d2AyDfhxvBHZc`, project `kh-home/smart-home`.
  Every recovered file was checked against its Vercel content SHA1, including
  the exercise photographs. Existing repository files that were not deployed
  (documentation, earlier migrations, and agent instructions) are retained.
- The complete Wellness frontend: nutrition, workouts, progress, profile setup,
  settings, food lookup, camera support, exercise illustrations, and offline sync.
- The UI fixes made during this session: centered bottom navigation, workout
  action clearance, month/year updates while scrolling the date wheel, removal
  of the redundant date input, and consumption-based nutrient rings.
- Updated household navigation, identity/session handling, boards, realtime
  state, and service worker code that were already present in production.
- Five deployed Supabase Edge Functions and their three shared source files:
  `pin-login`, `food-lookup`, `nutrition-analyze`, `health-maintenance`, and
  `health-account`. Shared files returned by multiple functions were identical.
- Eleven missing historical migration records from Supabase, archived in
  `supabase/recovered-migrations/` with their original versions and SQL.

`deployment-source-manifest.json` records the Vercel content hashes and Supabase
function versions. Recovery did not change any live database schema or records,
redeploy Edge Functions, or change production traffic.

## Work from Git from now on

1. Create a feature branch from the merged recovered source.
2. Make changes locally and run the relevant checks.
3. Push the branch and open a pull request.
4. Build and verify locally; branch and PR preview deployments are disabled.
5. Merge the reviewed pull request into `main`. The merge is the only permitted
   deployment trigger; the Git integration or a merge-triggered release workflow
   deploys that exact commit.

GitHub is the sole source of application and server code. Do not push directly
to `main`, upload source files directly to Vercel or Supabase, manually redeploy,
or promote an older build. These instructions also apply to automated agents
and are recorded in `AGENTS.md`.

`vercel.json` enables Git deployments for `main` and disables other branches.
The Vercel project is linked to `Haimindyk/smart-home`; preview deployments were
also disabled in the project settings. GitHub should require a pull request for
`main` and disallow direct pushes. The connected GitHub integration cannot
inspect or change branch protection, so that administrative setting still
needs verification by the repository owner.

Vercel's server-side deployment-source policy was unavailable on the current
Hobby plan (`pro_plan_required`). As a result, the service-level ability for a
privileged user to create a manual CLI/API deployment is not technically
blocked by that policy. Such deployments are prohibited by this repository's
workflow. No plan upgrade was performed.

Do not deploy the older main branch before this recovery is merged: that would
remove Wellness. Before enabling automatic deployments, verify that Vercel's
project Git connection points to `Haimindyk/smart-home` and the intended
production branch (`main`). This recovery does not change that connection.

## Local development and validation

Use Node 24 and the pinned `pnpm@11.25.0` package manager.

```bash
pnpm install --frozen-lockfile
cp .env.example .env.local
# Configure NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY locally.
pnpm dev
```

The current app signs in through the deployed `pin-login` Edge Function and
uses Supabase Auth sessions. Wellness records belong to the signed-in user.
Use the already-configured Supabase project for existing data; there is no
credential or private data export in this recovery.

Validation performed on the recovered source:

- Frozen-lockfile dependency installation.
- `pnpm build` (with placeholder public Supabase values for compilation only).
- `pnpm typecheck`.
- `pnpm lint` and `git diff --check`.
- Earlier isolated browser checks of the actual date-wheel/nutrient-ring
  components and CSS, covering viewport sizes, RTL/LTR, safe-area clearance,
  month/year transitions, and empty/partial/full nutrient progress.

The local placeholder build does not test an authenticated production session.
Vercel also built the deployed fixes successfully with the project configuration.

## Recovery limits

Vercel's deployed source did not include the original unit tests, Playwright
tests/configuration, or `scripts/test-health-db.sh`, although `package.json`
references these commands. Their original contents cannot be recovered from
this deployment. Do not report `pnpm test`, `test:e2e`, or `test:db` as passing
until those suites have been located or restored.

The migration archive preserves applied SQL, rather than inventing a new schema
migration. It is intentionally outside the automatically applied
`supabase/migrations/` directory. See its README before setting up a fresh
database or reconciling migration history.

Supabase function source is recovered, but its runtime secrets and project
settings are managed in Supabase. The five recovered functions currently use
`verify_jwt = false` at the gateway and implement their own checks in code.
Preserve the existing deployment settings when deploying a reviewed change.

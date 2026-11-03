# Wellness AI operations

GitHub is the sole source. No direct Vercel/Supabase uploads or branch preview
releases. This feature stays disabled until provider setup and quality evaluation
are complete. Manual nutrition/workout logging continues to work.

## Architecture and current limits

The app owns consent, data, validation, quotas and approval. Supabase Edge Functions
call replaceable pretrained Workers AI models: Qwen3-30B-A3B-FP8 for structured text,
Llama-3.2-11B-Vision for photo observations, and FLUX.1 Schnell for illustrations.
This is not a newly trained proprietary model or an always-on GPU server.

[Cloudflare pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/)
currently includes 10,000 neurons/account/day, resetting at 00:00 UTC. Use a
**dedicated Workers Free account**, without a paid Workers plan or prepaid gateway
credits. The app cannot verify account billing state from an inference token;
`CLOUDFLARE_FREE_ONLY=true` is an operator assertion, not a billing API check.
The free plan's refusal at exhaustion is the final no-spend boundary. Do not enable
this service on a paid/shared account expecting the app counter to guarantee cost.

The database atomically reserves up to 8,000 estimated neurons/day across all users.
Conservative reservations: photo 350, text 150, coach 450, illustration 200.
Per adult user/day: 5 photo analyses, 20 text analyses, 10 coach requests (including
restore proposals), 5 newly generated illustrations. One active job/user, two/account.
Reservations are estimates, not provider metering; failed/interrupted attempts retain
reservations. There is no retry loop, paid fallback or automatic model substitution.

Reference demonstrations and existing illustrations are reused. A generated program
may contain more image-less exercises than the day's image quota; placeholders do
not prevent saving or training. Unknown manual exercise names require an identified
catalog exercise rather than a guessed technique illustration.

## One-time service configuration

Configure through provider/CI secret settings; never commit or paste secret values.
No new Vercel client secrets are needed.

1. Create a restricted account-scoped Workers AI token in a dedicated Workers Free
   account, with Workers AI Run permissions. Confirm no paid Workers subscription
   or prepaid gateway billing is attached.
2. Review/accept the [Meta model terms](https://developers.cloudflare.com/workers-ai/models/llama-3.2-11b-vision-instruct/)
   using the documented initial `prompt: "agree"` request. This is an account/license
   action; the app does not silently accept terms on the operator's behalf.
3. In Supabase Edge Function secrets set `CLOUDFLARE_ACCOUNT_ID`,
   `CLOUDFLARE_AI_TOKEN`, `CLOUDFLARE_FREE_ONLY=true`, and initially
   `WELLNESS_AI_ENABLED=false`. Only set the latter to `true` after the synthetic
   model checks and product evaluation in `wellness-product-research.md` pass.
4. In the GitHub `production` environment set secrets `SUPABASE_DB_URL` (SSL
   session/direct PostgreSQL URL) and `SUPABASE_ACCESS_TOKEN`; set variable (or environment secret)
   `SUPABASE_PROJECT_REF` to the existing project. Restrict that environment to main
   if repository settings allow it. Never put a database password in the workflow.
5. Review and merge the PR. The release workflow checks out exactly
   `pull_request.merge_commit_sha`, validates, applies the additive migration in one
   SQL transaction, then deploys only the four functions from that commit. It has
   no manual dispatch or preview deployment. Functions perform their own
   `auth.getUser` and membership checks (`--no-verify-jwt` only disables the gateway's
   legacy JWT check, not application authentication).

Historical migrations were recovered with mixed numbering and timestamps. The
release deliberately applies only `20261103200306_wellness_ai.sql` under a transaction
and advisory lock, and records its version in Supabase migration history. It does
not replay or repair historical migrations. Do not run a blanket `supabase db push`
until that separate history reconciliation has been completed. Existing project
schema, its private module deletion RPC and migration-history table are prerequisites.
The local SQL test creates these prerequisites and runs the actual new migration.

Vercel deploys main through the existing Git integration. The frontend's capability
probe keeps AI unavailable until the backend migration/function/provider are ready;
its manual features work during this additive rollout. Backend release failures
must be resolved in a follow-up PR merged to main, not a manual deploy.

## Privacy, retention and rollback

- New explicit consent names Cloudflare; legacy Google consent never grants it.
  Adults only. Settings can revoke consent; it stops new inference requests.
- Only necessary request text, photo or exercise/performance context is sent. No
  automatic transmission of name, PIN, user ID or full body profile. User free text
  can contain identifying details; the UI asks users not to include them.
- [Workers AI data usage](https://developers.cloudflare.com/workers-ai/platform/data-usage/)
  states Customer Content is not used for model training. This is provider policy,
  not a claim that the app is an independently trained model.
- Photos are private, owner-prefixed and signed briefly. Photo retention is opt-in
  per meal. Unreferenced originals are removed by existing daily maintenance after
  24 hours. Saved meal photos and illustration rows remain referenced.
- Generated results and approved snapshots expire after 30 days via daily maintenance.
  The UI offers up to the most recent 30 snapshots. Undo requires that the current
  plan still matches the applied version; no stale overwrite. Nutrition/workout
  module deletion transactionally deletes its corresponding AI content and snapshots;
  storage cleanup preserves images belonging to the other module.
- Daily usage counters contain counts only, expire after 30 days, and are not reset
  by deleting one module (to prevent quota bypass). Full health deletion removes them.
- No raw images, request text, provider responses or secrets go into logs. Errors
  sent to the client are bounded categories. DB job errors retain categories only.
- To stop inference, disable `WELLNESS_AI_ENABLED` in server configuration. Existing
  owned proposal history/apply/reject remain usable without provider availability.
  Revert application/backend changes only by a new Git PR and merge. Keep the
  additive data tables for recovery; do not drop them to roll back the UI.

## Local validation

`pnpm test` runs pure validation/provider tests and real Postgres (PGlite) tests for
RLS, grants, quotas, atomic multi-plan approvals, idempotency and deletion.
`pnpm typecheck`, `pnpm lint`, `pnpm build`, and the pinned Deno check used by CI
cover the client and Edge runtime. After building, `pnpm test:wellness:ui` exercises
the actual components with synthetic services in Chromium (install with
`pnpm exec playwright install chromium`, or set `CHROMIUM_PATH` to a system browser).
It checks Hebrew/English mobile approval and meal confirmation flows. These do not establish live model accuracy or
production provider connectivity. No private photos are used by automated tests.


Owned adapter training and the separate opt-in contribution path are documented in
[ml/README.md](../ml/README.md). The training registry is intentionally empty until
real training, held-out evaluation and a matching runtime probe succeed. Inference
consent does not authorize training; contributions are submitted individually and
remain unreviewed until curated. Training submissions have separate retention until
withdrawal/module deletion, rather than the inference jobs' 30-day retention.

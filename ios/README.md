# Yachad (יחד) — the iOS companion app

A native SwiftUI iOS app that takes the ideas from the K&H website (shared
sections, tasks with unlimited-depth subtasks, a shopping flavor, recurring
house chores, a calendar, instant search) and generalizes them: instead of
one implicit household, **anyone can create their own shared "area"** and
invite household members or friends into it via a link or QR code. The
area's creator approves each request and picks **read-only** or
**read & write** for that person. There is still no login/signup —
identification is just a name or nickname, exactly like the website.

**This does not touch the website or its Supabase project in any way.**
Everything here — the app and its backend — is new and additive:

- The app lives entirely under `ios/`; nothing in `src/`, `supabase/`, or
  the website's config changed.
- The backend is a **separate Supabase project** (`ios/backend/migrations/`),
  independent of `supabase/migrations/` at the repo root. The website's
  single-implicit-workspace model (see the root `README.md`'s "Access
  model") doesn't generalize to multi-tenant areas without either bolting
  workspace_id onto every table or standing up a new project — a new
  project is the one that can't accidentally regress the site people are
  already using.

## Why "separate Supabase project" instead of new tables in the existing one

The website's whole schema — `is_member()`, every RLS policy, the
`members` table — assumes **one** shared workspace with no `area_id`
anywhere. Multi-tenancy (many areas, invite/approve, per-area roles) needs
a different shape for nearly every table (`area_id` columns, different RLS
predicates, different membership semantics). Reusing the site's project
would mean either duplicating every table under new names anyway (no
real benefit to sharing the project) or changing the site's own tables
(the one thing this task explicitly rules out). A second project keeps the
two completely isolated: the site's data, RLS, and uptime are never at
risk from anything this app does.

## Access model — no login, but multi-tenant

Same spirit as the website's "no login" model, extended with real
per-area gating:

- A device generates a random id once (`UserDefaults`, not Keychain — it's
  an attribution key, not a secret, same reasoning as the website's
  localStorage identity) and sends it as an `x-device-id` header on every
  request.
- Row Level Security on the new backend keys off that header (see
  `ios/backend/migrations/0002_access_control.sql`): a device can only read
  an area once it has an `approved` row in `area_members` for it, and can
  only write if that row's `role` is `owner`, `manager`, or `editor`.
- Four roles: `owner` (the creator, exactly one, fixed — no ownership
  transfer in v1), `manager` (everything the owner can do except delete the
  area or touch the owner's own row — including approving/rejecting
  joiners and appointing further managers), `editor` (read & write
  content), `viewer` (read-only).
- Each area has a `join_policy`: `manual` (default — every request waits
  for the owner or a manager to approve it and pick a role) or `auto`
  (anyone holding the link/QR is approved immediately, with a configurable
  default role). Either way, no login is ever required — just a nickname.
- Creating or joining an area only happens through SECURITY DEFINER RPCs
  (`create_area`, `request_join_area`, `approve_area_member`,
  `delete_area`) — there's no direct insert policy on
  `areas`/`area_members`, so a device can never forge membership in
  someone else's area or grant itself a role, and only the owner can
  delete the area outright.

## What's shipped vs. deferred

Following the same "ship the core, defer the rest cleanly" approach as the
website's own README:

**Shipped**: areas (create/rename via emoji+name), invite via link + QR
code, join requests with owner/manager approval (read-only, read & write,
or manager), an area-level toggle between "requires approval" and "anyone
with the link joins automatically" (with a configurable default role for
auto-join), an owner can appoint further managers who get the same
approve/appoint/remove powers, member management, sections (tasks/shopping/
chores/info), tasks with unlimited-depth subtasks and **multiple**
assignees (new tasks auto-assign whoever created them), shopping-flavored
fields (quantity/unit/price/brand), house chores with daily/weekly/monthly/
as-needed recurrence + completion history, a month-grouped calendar
(birthdays/medical/other, yearly recurrence), instant client-side search, a
lightweight recent-activity log, **drag-and-drop reordering** (tasks within
a section, shopping items, sections on the dashboard), **an undo toast
after every delete**, **push notifications** (join requests, approvals,
task assignments, a daily due-today digest), Hebrew (RTL, default) +
English (LTR), Realtime sync per area.

**Deliberately deferred** (same reasoning as the website's own Phase 2
list — clean extension points exist, but each deserves its own pass):

- **Offline cache / write queue.** The website has a full IndexedDB
  read-cache + replay-on-reconnect queue; this app assumes connectivity
  and refetches on reconnect. Worth adding with SwiftData once the core
  flows are validated in Xcode.
- **Price comparison / barcode scanning / AI assistant.** These are tied to
  Israeli grocery-chain scraping and an LLM-backed assistant with its own
  cron infrastructure on the website; out of scope for a general-purpose
  "shared note with anyone" app, per explicit request.
- **Area ownership transfer / deleting a single member's content.**
- **Subtask reordering.** Drag-and-drop reorders top-level tasks/items
  (a subtask tree moves as a unit with its parent); reordering *within* a
  subtask list isn't wired up yet.

## Setup

### 1. Create the Supabase project

1. Create a **new, separate** Supabase project (not the website's).
2. Apply the migrations in `ios/backend/migrations/` **in order**, via the
   SQL editor, the Supabase CLI, or the Supabase MCP tools.
3. Copy the project URL and anon/publishable key.

### 2. Configure the app

```bash
cd ios
cp Yachad/Config/Secrets.xcconfig.example Yachad/Config/Secrets.xcconfig
# edit Secrets.xcconfig: SUPABASE_URL + SUPABASE_ANON_KEY
```

`Secrets.xcconfig` is git-ignored. The anon key is meant to be public (it
ships inside the app bundle) — access is enforced server-side by RLS, see
above.

### 3. Generate and open the Xcode project

This repo ships Swift source + an [XcodeGen](https://github.com/yonaskolb/XcodeGen)
spec (`project.yml`) rather than a hand-written/committed `.xcodeproj` —
safer to regenerate than to hand-edit a binary-ish project file, and there
is no macOS/Xcode available in the environment this was written in to
generate and commit one directly.

```bash
brew install xcodegen   # once
cd ios
xcodegen generate
open Yachad.xcodeproj
```

Xcode will resolve the `supabase-swift` Swift Package dependency
automatically on first build. Pick a simulator (iOS 17+) and run.

### 4. Push notifications (optional, but "shipped" assumes you do this)

Push has three moving parts, none of which can be provisioned from this
repo alone — they all need your own Apple Developer account and Supabase
project:

1. **APNs Auth Key.** In [Apple Developer → Certificates, IDs & Profiles →
   Keys](https://developer.apple.com/account/resources/authkeys/list),
   create a key with the "Apple Push Notifications service (APNs)" capability
   and download the `.p8` file (you only get one chance to download it).
   Note the **Key ID** and your **Team ID**.
2. **Deploy the Edge Function** (`ios/backend/functions/send-push/`):
   ```bash
   supabase functions deploy send-push --no-verify-jwt --project-ref <your-ref>
   supabase secrets set --project-ref <your-ref> \
     APNS_KEY_ID=<key id> \
     APNS_TEAM_ID=<team id> \
     APNS_BUNDLE_ID=com.haimindyk.yachad \
     APNS_ENVIRONMENT=sandbox \
     PUSH_EDGE_SECRET=$(openssl rand -hex 32) \
     APNS_PRIVATE_KEY="$(cat AuthKey_XXXXXXXXXX.p8)"
   ```
   (`APNS_ENVIRONMENT=sandbox` while testing from Xcode/TestFlight-via-Xcode;
   switch to `production` once you're distributing through TestFlight/App
   Store proper — see the entitlements note below.)
3. **Tell Postgres how to reach the function**, using the *same*
   `PUSH_EDGE_SECRET` from step 2, in the Supabase SQL editor:
   ```sql
   select vault.create_secret('https://<your-ref>.functions.supabase.co/send-push', 'push_edge_url');
   select vault.create_secret('<same PUSH_EDGE_SECRET as above>', 'push_edge_secret');
   ```
   Until both secrets exist, `notify_devices()` (migration `0005`) silently
   no-ops — the rest of the app works fine without push configured.
4. If `create extension pg_net` / `pg_cron` in migration `0005` errors on
   your plan, enable them instead from the Supabase dashboard's
   **Database → Extensions**, then re-run the rest of that migration file.

**In Xcode**: the entitlements file (`Yachad/Yachad.entitlements`) ships
with `aps-environment: development`. For a TestFlight/App Store archive,
either flip that to `production`, or let Xcode's automatic signing manage
it for you if your team has that configured — check before shipping, since
a mismatched entitlement means push silently fails to register.

Once set up: open the app → Settings → "Enable notifications". A join
request, an approval, or being assigned to a task all push immediately; a
"due today" digest for tasks/chores fires once a day (see
`send_due_today_reminders()` / the `pg_cron` schedule in migration `0005`).

### A note on the Supabase Swift SDK surface

This was written without access to Xcode/macOS to compile against, so
while the Supabase calls in `Yachad/Services/*.swift` follow the
documented `supabase-swift` v2 patterns (`.from().select()/.insert()/
.update()/.rpc()`, `channel().postgresChange()`), the exact method
signatures can shift between SDK versions. If the first build turns up
signature mismatches, they should be narrow/mechanical fixes — the
`RealtimeSyncManager` (which uses the newer channel/`postgresChange` API)
is the most likely spot to need adjusting to whatever `supabase-swift`
version Xcode resolves.

## Architecture notes

- **`x-device-id` header ≈ the website's localStorage identity**, just
  extended to also gate access (see "Access model" above).
- **Unified `tasks` table** (subtasks via `parent_task_id`, shopping
  fields nullable outside shopping sections) — same design as the website,
  reimplemented against the new per-area schema.
- **`AreaWorkspaceStore`** (`Yachad/App/AreaWorkspaceStore.swift`) is the
  live state for one open area — sections/tasks/chores/events/members/
  activity — refetched on load and on every Realtime change.
  Simplification vs. the website: changes trigger a full refetch of that
  screen's data (debounced) instead of row-level optimistic reconciliation
  — simpler, and plenty fast for the household/friend-group sizes this
  targets.
- **Fractional indexing** (`Yachad/Services/FractionalIndex.swift`) is a
  from-scratch base62 port of the same idea as the website's
  `lib/ordering/rank.ts` (so concurrent reorders don't collide), since this
  is a separate backend with its own `position` columns.
- **Invite links** use a custom `yachad://join?code=…` URL scheme rather
  than a universal link — no domain or hosted
  `apple-app-site-association` file required. The bare invite code (shown
  under the QR) works too, for "just tell me the code."
- **Undo** (`AreaWorkspaceStore.showUndo`/`performUndo`) is generic across
  every entity: every delete call site passes a message + a `restore`
  closure (usually just the matching service's `restore(id:)`, which clears
  `deleted_at`); one `UndoToastView`, mounted once in `AreaDashboardView`,
  covers all five tabs.
- **Push** is device-scoped, not area- or person-scoped (`push_tokens`,
  keyed by `device_id`) — a device holding membership in three areas gets
  one token covering all of them. Delivery is Postgres trigger → `pg_net` →
  a Supabase Edge Function → APNs; nothing calls Apple directly from the
  app or from client code.

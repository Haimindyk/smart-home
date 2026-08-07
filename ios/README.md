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
  only write if that row's `role` is `owner` or `editor`.
- Creating or joining an area only happens through two SECURITY DEFINER
  RPCs (`create_area`, `request_join_area`) — there's no direct insert
  policy on `areas`/`area_members`, so a device can never forge
  membership in someone else's area or grant itself a role.
- The area's owner approves each pending request and picks the role;
  that's the entire "permission system."

## What's shipped vs. deferred

Following the same "ship the core, defer the rest cleanly" approach as the
website's own README:

**Shipped**: areas (create/rename via emoji+name), invite via link + QR
code, join-request + owner approval with read-only/read-write roles,
member management, sections (tasks/shopping/chores/info), tasks with
unlimited-depth subtasks, shopping-flavored fields (quantity/unit/
price/brand), house chores with daily/weekly/monthly/as-needed recurrence
+ completion history, a month-grouped calendar (birthdays/medical/other,
yearly recurrence), instant client-side search, a lightweight recent-
activity log, Hebrew (RTL, default) + English (LTR), Realtime sync per area.

**Deliberately deferred** (same reasoning as the website's own Phase 2
list — clean extension points exist, but each deserves its own pass):

- **Offline cache / write queue.** The website has a full IndexedDB
  read-cache + replay-on-reconnect queue; this app assumes connectivity
  and refetches on reconnect. Worth adding with SwiftData once the core
  flows are validated in Xcode.
- **Push notifications.** Needs APNs certificates/keys and a notification
  service — orthogonal to the sharing model this task asked for.
- **Price comparison / barcode scanning / AI assistant.** These are tied to
  Israeli grocery-chain scraping and an LLM-backed assistant with its own
  cron infrastructure on the website; out of scope for a general-purpose
  "shared note with anyone" app.
- **Drag-and-drop reordering UI.** The backend already supports it
  (fractional-indexing `position` columns, `FractionalIndex.swift`); only
  the SwiftUI drag gesture wiring is deferred.
- **Area ownership transfer / deleting a single member's content.**

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

# K&H

A realtime, collaborative household PWA that replaces a shared Apple Note. Built with Next.js
(App Router), Supabase (Postgres + Realtime + Storage), TailwindCSS, and shadcn/ui.

Sections, tasks (with unlimited-depth subtasks), a dedicated shopping flavor, and a house-chores
view with recurring schedules all live in one Supabase project and sync instantly across every
device via Supabase Realtime. It works offline (cached reads + a queued-write sync-on-reconnect),
installs as a PWA on iPhone/Android/desktop, and supports Hebrew (RTL, default) and English.

## Access model — read this first

**There is no login.** By explicit request, this app has zero auth friction: anyone with the
deployed URL can open it and use it immediately, the same way the Apple Note it replaces worked.
A lightweight "who's here?" picker just sets an attribution name (Haim / Koren / Guest) in
`localStorage` — it is **not** a security boundary.

Practical implications:

- Supabase Row Level Security is enabled on every table, but `is_member()` currently returns
  `true` unconditionally — the database is reachable by anyone holding the (public, client-side)
  Supabase anon key, which is unavoidable for a browser app anyway.
- The real access control is **possessing the app URL**. Treat it like a shared Google Doc link:
  - Don't post the URL somewhere public or indexable.
  - Add a `robots.txt` disallow / `noindex` header before deploying if you want to be extra safe.
  - If you ever want a real gate, Supabase Anonymous Sign-In is a one-line upgrade: flip
    "Enable anonymous sign-ins" on in the Supabase dashboard, call `supabase.auth.signInAnonymously()`
    once on load, and tighten `is_member()` (see `supabase/migrations/0002_open_access.sql`) back to
    `select auth.uid() is not null`. Every table's RLS policy already routes through that single
    function, so this is a one-line change, not a rewrite.

## Stack

- **Next.js 16** (App Router, Turbopack, TypeScript strict)
- **Supabase**: Postgres, Realtime (`postgres_changes`), Storage, RLS
- **TailwindCSS v4** + **shadcn/ui** (Base UI primitives, RTL-aware by default)
- **dnd-kit** for drag-and-drop reordering
- **fractional-indexing** for collision-free concurrent reordering
- **Zustand** for client state (normalized by id) + **idb** for the offline cache/mutation queue
- **fuse.js** for instant client-side fuzzy search
- **next-themes** for dark/light, a small custom locale store for he/en + RTL/LTR

## Getting started

```bash
pnpm install
cp .env.example .env.local   # fill in your Supabase project URL + anon key
pnpm dev
```

Open http://localhost:3000. The dashboard, sections, and house chores are already seeded with
real data (see "Initial data" below) the first time you point this at a fresh Supabase project.

### Setting up Supabase

1. Create a free Supabase project.
2. Apply the migrations in `supabase/migrations/` in order (via the Supabase SQL editor, the
   Supabase CLI, or the Supabase MCP tools). `0003_seed_kh_data.sql` is idempotent — it only
   seeds if `sections` is empty, so it's safe to run against a fresh project and a no-op
   afterwards.
3. Copy your project URL and anon/publishable key into `.env.local` (see `.env.example`).

## Architecture notes

- **Single implicit workspace.** There's no `workspaces` table — the whole app is one shared
  household, so "are you allowed to see this row" collapses to `is_member()` (see above), and
  every other table's RLS policy is just `using (is_member())`.
- **Unified `tasks` table.** Regular tasks, subtasks (self-referential `parent_task_id`), and
  shopping items are the same table with nullable shopping-flavored columns (`quantity`, `price`,
  `brand`, ...). One realtime feed, one optimistic-write path, one drag-and-drop implementation —
  see the design rationale at the top of `supabase/migrations/0001_init.sql`.
- **Chores are separate** (`chores` + `chore_completions`): a chore is a recurring *rule* plus an
  append-only completion log, so "who did Tuesday's vacuuming" stays queryable forever while the
  rule itself just flips pending → done → pending. Completing a chore calls the `complete_chore`
  RPC, which computes the next occurrence server-side (never trust client clocks for scheduling).
- **Ordering** uses fractional-indexing (`lib/ordering/rank.ts`), so two people reordering at the
  same time can't collide the way integer positions would.
- **Realtime + optimistic UI** (`lib/store/app-store.ts`, `lib/realtime/use-realtime-sync.ts`):
  writes apply to the Zustand store immediately, then hit Supabase; the same row echoing back
  over `postgres_changes` is reconciled by last-write-wins on `updated_at`, so it's a no-op, not a
  flicker.
- **Offline**: reads are cached in IndexedDB (`lib/offline/db.ts`) and hydrate the app instantly
  even with no connection; writes made while offline are queued and replayed in order on
  reconnect (`lib/offline/queue.ts`). This is intentionally not a CRDT — for a household of a
  couple of people, last-write-wins on reconnect is the honest, simple answer.
- **PWA**: a hand-written service worker (`public/sw.js`) caches the app shell for instant offline
  loads. Next.js 16 builds with Turbopack by default, which the usual webpack-based PWA plugins
  don't support, so this avoids that dependency entirely instead of shipping something broken.
- **i18n/RTL**: `he` (RTL) is the default locale with a full `en` (LTR) translation of the app
  chrome; user-entered content (task titles, notes) is wrapped to compute its own bidi direction
  so mixed Hebrew/English/number text never scrambles. All Tailwind classes use logical properties
  (`ps-`/`pe-`/`ms-`/`me-`/`start-`/`end-`) so the whole UI mirrors by flipping `dir`.

## What's here vs. Phase 2

Shipped: auth-free K&H workspace, dashboard with section cards (progress/pending/completed/last
edited/quick-add), unlimited sections (create/rename/reorder/delete), tasks with unlimited-depth
subtasks and rich fields (notes, due date, priority, tags, emoji, assignee, link auto-detect),
shopping-flavored fields, a house-chores view with daily/weekly/monthly/as-needed recurrence and
completion history, drag-and-drop reordering (tasks within a section, sections on the dashboard —
moving a task to a *different* section is a "Move to..." action rather than a cross-list drag, a
deliberate v1 simplification), true Supabase Realtime sync with optimistic UI, offline read cache
+ write queue, soft-delete with an undo toast, global instant search, dark/light, Hebrew RTL +
English, PWA installability.

Deliberately deferred (clean extension points exist, but building these properly deserved their
own pass rather than being rushed into this one):

- **Calendar view** (trips/appointments/birthdays/reminders on a month grid)
- **Push notifications** (due-today/overdue/daily-summary — needs VAPID keys + a service worker
  push handler; iOS Safari requires the PWA be installed to the home screen for this to work at
  all)
- **NLP quick-add** beyond the basic date extraction already in `lib/nlp/quick-add-parse.ts`
  (today/tomorrow, dd/mm dates in Hebrew and English)
- **Full activity log UI** (the `activity_log` table and soft-delete/restore already exist; a
  browsable "who changed what, when" screen with multi-step undo does not)

## Initial data

The real family note (Hebrew, previously a shared Apple Note) was parsed into structured sections,
tasks, subtasks, completed items, and house chores in `supabase/migrations/0003_seed_kh_data.sql`.
It runs automatically the first time migrations are applied to an empty project.

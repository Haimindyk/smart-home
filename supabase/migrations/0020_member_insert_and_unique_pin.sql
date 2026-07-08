-- Self-serve "add a household member" flow needs two things the schema never
-- had, since every member so far was seeded by hand in a migration:
--   1. An INSERT policy on members — there was only ever select/update ones.
--   2. A DB-level guarantee that PINs are unique, since the PIN login screen
--      (identity-gate.tsx) matches on it and two members sharing a PIN would
--      be ambiguous. Partial index so members without a PIN yet aren't
--      blocked from all having null.
-- Gated by is_member() like everything else in this app (see
-- 0002_open_access.sql) — there's no real access control, just the same
-- no-op predicate every table's policies already use.

create policy "members can insert new members" on public.members
  for insert with check (public.is_member());

create unique index members_pin_unique_idx on public.members (pin) where pin is not null;

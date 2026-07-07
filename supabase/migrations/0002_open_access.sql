-- Drop the email-allowlist gate: the user wants zero-friction access (anyone
-- with the link/app can use it, like the original shared Apple Note) with no
-- login step at all. Enabling Supabase's "anonymous sign-ins" project setting
-- isn't reachable from a migration (it's a dashboard/Management-API toggle),
-- so rather than ship an auth path that silently doesn't work until someone
-- flips that switch, access is governed the same way the Apple Note was:
-- possession of the (unguessable) app URL. RLS stays on and every policy
-- still runs through is_member() as a single choke point, so tightening this
-- later (e.g. turning on anonymous or real auth) is a one-line change here,
-- not a rewrite of every table's policies.

drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.link_member_on_signup();

create or replace function public.is_member()
returns boolean
language sql
stable
as $$
  select true;
$$;

-- members.user_id / email no longer gate anything; keep the columns as
-- optional metadata (nice-to-have contact info) rather than drop them.
alter table public.members alter column user_id drop not null;
drop policy if exists "members can update their own row" on public.members;
create policy "members can update their own row" on public.members
  for update using (public.is_member()) with check (public.is_member());

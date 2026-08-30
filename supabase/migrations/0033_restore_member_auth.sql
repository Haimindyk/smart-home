-- Migration 0002 deliberately dropped real per-member authentication in
-- favor of "possession of the link" access (see its comment: "tightening
-- this later ... is a one-line change here, not a rewrite of every table's
-- policies"). That moment has arrived: private boards (see migration 0034)
-- need a real, DB-enforced notion of "which member is this request" that
-- the household's shared anon key alone can't provide — is_member() being
-- unconditionally true for anyone with the link is fine for the household's
-- own shared data, but can't be the gate for something one member
-- deliberately wants hidden from another.
--
-- This migration only restores the *linkage* between a member row and a
-- real auth.users identity (undoing exactly what 0002 dropped) — it does
-- NOT touch is_member() or any existing table's RLS, so every existing
-- table/flow keeps working exactly as before. Only the new board-scoped
-- policies in 0034 actually rely on this.
create or replace function public.link_member_on_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.members
    set user_id = new.id
    where lower(email) = lower(new.email) and user_id is null;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.link_member_on_signup();

-- Resolves the calling request's own member row via its real auth session
-- (set by the pin-login Edge Function — see supabase/functions/pin-login).
-- Null for any request without a matching signed-in session (e.g. the
-- assistant Edge Function, which calls in with the plain anon key and no
-- user JWT) — board access checks treat that the same as "not a member of
-- this board", which is the correct, safe default.
create or replace function public.current_member_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.members where user_id = auth.uid();
$$;

-- Read only by the pin-login Edge Function's service-role client — the
-- pepper it needs to derive each member's synthetic Supabase Auth password
-- (see that function for the full flow). Provisioned out-of-band, same as
-- every other secret in this project (see 0006's get_push_config comment):
--   select vault.create_secret(encode(gen_random_bytes(32), 'hex'), 'pin_login_pepper', 'HMAC pepper for pin-login synthetic passwords');
create or replace function public.get_pin_login_pepper()
returns text
language sql
stable
security definer
set search_path = public, vault
as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'pin_login_pepper';
$$;

revoke all on function public.get_pin_login_pepper() from public, anon, authenticated;
grant execute on function public.get_pin_login_pepper() to service_role;

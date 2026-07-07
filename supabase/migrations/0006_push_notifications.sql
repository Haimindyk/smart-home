-- Push notification infra: a subscription per browser/device (tagged with
-- whichever member set it up — there's no real account system, see the
-- "no auth" note in earlier migrations), per-member preferences, and a
-- trigger that fans every activity_log insert out to an Edge Function that
-- does the actual sending. Hooking into activity_log (rather than the
-- individual tasks/chores/sections tables) means every logical change
-- produces exactly one push attempt by construction, since that's already
-- the single place all of those writes converge (see 0004's log_activity()
-- and 0005's log_chore_completion()).

create extension if not exists pg_net with schema extensions;

-- ---------------------------------------------------------------------------
-- push_subscriptions: one row per (browser, member) pairing
-- ---------------------------------------------------------------------------
create table public.push_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  member_id   uuid references public.members(id) on delete cascade,
  endpoint    text not null unique,
  p256dh      text not null,
  auth        text not null,
  user_agent  text,
  created_at  timestamptz not null default now()
);

alter table public.push_subscriptions enable row level security;

create policy "members full access to push_subscriptions" on public.push_subscriptions
  for all using (public.is_member()) with check (public.is_member());

-- ---------------------------------------------------------------------------
-- notification_prefs: per-member on/off switches (defaults all-on)
-- ---------------------------------------------------------------------------
create table public.notification_prefs (
  member_id       uuid primary key references public.members(id) on delete cascade,
  on_create       boolean not null default true,
  on_complete     boolean not null default true,
  on_assigned_me  boolean not null default true,
  on_shopping     boolean not null default true,
  muted           boolean not null default false,
  updated_at      timestamptz not null default now()
);

alter table public.notification_prefs enable row level security;

create policy "members full access to notification_prefs" on public.notification_prefs
  for all using (public.is_member()) with check (public.is_member());

-- ---------------------------------------------------------------------------
-- Fan out every activity_log insert to the send-push Edge Function.
-- Auth between the DB and the function is a shared secret kept in Vault
-- (`push_trigger_secret`, created out-of-band — see the PR description,
-- never checked into a migration file in plaintext), not the DB's service
-- role key, so this trigger stays least-privilege.
-- ---------------------------------------------------------------------------
create or replace function public.notify_push()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_secret text;
begin
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'push_trigger_secret';

  if v_secret is null then
    -- Not configured yet (e.g. a fresh environment before secrets are set up) — no-op.
    return null;
  end if;

  perform net.http_post(
    url := 'https://ogoxwhebqxjligxeqnqd.functions.supabase.co/send-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_secret),
    body := to_jsonb(NEW)
  );

  return null;
end;
$$;

drop trigger if exists activity_log_notify_push on public.activity_log;
create trigger activity_log_notify_push
  after insert on public.activity_log
  for each row execute function public.notify_push();

-- ---------------------------------------------------------------------------
-- The Edge Function has no deploy-time secrets of its own (only the
-- auto-injected SUPABASE_URL/SUPABASE_ANON_KEY every function gets by
-- default) — it fetches the VAPID keypair at request time by presenting the
-- same shared secret it was invoked with. This doubles as the request's
-- authentication: a bogus/missing secret raises and the function never
-- learns the keys. VAPID keys themselves are created out-of-band via
-- vault.create_secret('...', 'vapid_public_key' | 'vapid_private_key'),
-- never checked into a migration file in plaintext.
-- ---------------------------------------------------------------------------
create or replace function public.get_push_config(p_secret text)
returns table (vapid_public_key text, vapid_private_key text)
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_trigger_secret text;
begin
  select decrypted_secret into v_trigger_secret from vault.decrypted_secrets where name = 'push_trigger_secret';
  if v_trigger_secret is null or v_trigger_secret != p_secret then
    raise exception 'invalid push trigger secret';
  end if;

  return query
    select
      (select decrypted_secret from vault.decrypted_secrets where name = 'vapid_public_key'),
      (select decrypted_secret from vault.decrypted_secrets where name = 'vapid_private_key');
end;
$$;

grant execute on function public.get_push_config(text) to anon, authenticated;

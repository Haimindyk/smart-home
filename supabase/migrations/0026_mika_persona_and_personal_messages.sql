-- Mika ("מיקה"): the household asked for the assistant to feel like a real
-- member of the family rather than a generic tool — a name, a gender, and a
-- new capability where she builds an individual relationship with each
-- person (noticing when someone's been quiet, an inside joke), separate from
-- the household-wide broadcasts (joke/digest/insights) that already exist.
-- Louis (the dog's placeholder member row) is excluded — he can't read a
-- notification — and so is Mika's own row.
--
-- Like every other "privacy" boundary in this app (see 0002_open_access.sql),
-- this is UX-level, not enforced by RLS: is_member() is unconditionally true
-- for anyone with the link, so a private message is only private in that (a)
-- the UI only ever shows a member their own rows, and (b) the push
-- notification itself is hardware-scoped to that member's own registered
-- device — nobody's actually locked out at the database layer, consistent
-- with this whole app's "no real auth" design.

update public.members set display_name = 'מיקה' where email = 'assistant@kh.family';

-- ---------------------------------------------------------------------------
-- Which members Mika builds a personal relationship with — off for her own
-- row and for Louis, on for everyone else by default.
-- ---------------------------------------------------------------------------
alter table public.members add column is_ai_companion_target boolean not null default true;

update public.members set is_ai_companion_target = false
where email = 'assistant@kh.family' or display_name = 'לואי';

-- Last time this member chatted with Mika directly (see the Edge Function's
-- chat branch) — lets her notice "it's been a while" honestly instead of
-- that being a canned line.
alter table public.members add column last_chat_at timestamptz;

-- A dedicated on/off switch for Mika's personal check-ins, independent of
-- on_broadcast (household-wide messages) — muting one shouldn't mute the other.
alter table public.notification_prefs add column on_ai_personal boolean not null default true;

-- ---------------------------------------------------------------------------
-- ai_private_messages: Mika's one-on-one notes. Never routed through
-- activity_log (which the whole household reads via History) — kept in its
-- own table so it never surfaces in anyone else's feed.
-- ---------------------------------------------------------------------------
create table public.ai_private_messages (
  id          uuid primary key default gen_random_uuid(),
  member_id   uuid not null references public.members(id) on delete cascade,
  summary     text not null,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);

create index ai_private_messages_member_idx on public.ai_private_messages (member_id, created_at desc);

alter table public.ai_private_messages enable row level security;

create policy "members full access to ai_private_messages" on public.ai_private_messages
  for all using (public.is_member()) with check (public.is_member());

alter publication supabase_realtime add table public.ai_private_messages;

-- ---------------------------------------------------------------------------
-- Push for a new personal message — targets ONLY that one member's own
-- subscriptions (see send-push's `action === 'personal'` handling), never
-- the "everyone but the actor" household fan-out the other triggers use.
-- ---------------------------------------------------------------------------
create or replace function public.notify_push_ai_private_message()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, vault
as $$
declare
  v_secret text;
  v_actor_id uuid;
begin
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'push_trigger_secret';

  if v_secret is null then
    return null;
  end if;

  select id into v_actor_id from public.members where email = 'assistant@kh.family';

  perform net.http_post(
    url := 'https://ogoxwhebqxjligxeqnqd.functions.supabase.co/send-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_secret),
    body := jsonb_build_object(
      'entity_type', 'ai_private_message',
      'entity_id', NEW.id,
      'action', 'personal',
      'actor_id', v_actor_id,
      'target_member_id', NEW.member_id,
      'summary', NEW.summary,
      'created_at', NEW.created_at
    )
  );

  return null;
end;
$$;

drop trigger if exists ai_private_messages_notify_push on public.ai_private_messages;
create trigger ai_private_messages_notify_push
  after insert on public.ai_private_messages
  for each row execute function public.notify_push_ai_private_message();

-- ---------------------------------------------------------------------------
-- Cron: pokes the assistant daily; the Edge Function itself decides, per
-- member, whether enough time has passed since Mika's last personal message
-- to them (see the "personal_checkin" intent) — so this fires daily but a
-- given person only actually hears from her every few days.
-- ---------------------------------------------------------------------------
create or replace function public.check_ai_personal_checkin()
returns void
language plpgsql
security definer
set search_path = public, extensions, vault
as $$
declare
  v_secret text;
begin
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'assistant_trigger_secret';
  if v_secret is null then
    return;
  end if;

  perform net.http_post(
    url := 'https://ogoxwhebqxjligxeqnqd.functions.supabase.co/assistant',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_secret),
    body := jsonb_build_object('intent', 'personal_checkin')
  );
end;
$$;

select cron.schedule('ai-personal-checkin', '0 10 * * *', $$select public.check_ai_personal_checkin();$$);

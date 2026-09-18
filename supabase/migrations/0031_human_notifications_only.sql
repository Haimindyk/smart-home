-- The household asked for one rule: a notification only ever fires when a
-- *person* does something — added, completed or deleted an item, or
-- deliberately sent a broadcast (see send-push's action matrix for the exact
-- set, which pure edits like a rename deliberately stay out of). No
-- scheduled reminders, and nothing Jessica (the assistant) sends on her own.
--
-- Three separate sources of non-human notifications existed; all three go:
--
--   1. Scheduled sweeps that manufactured activity_log rows nobody wrote —
--      due-date reminders (0009) and family-event reminders (0010).
--   2. Jessica's proactive cron intents — insights (0023), weekly digest
--      (0025), personal check-ins (0026), Shabbat greeting (0027). Same
--      treatment the daily joke already got in 0029: unschedule the job and
--      drop the poke function. The Edge Function no longer accepts those
--      intents either; chat (which only ever answers a human) is untouched.
--   3. The two push triggers Jessica's own writes rode on — ai_suggestions
--      (0024) and ai_private_messages (0026).
--
-- notify_push() then gets a belt-and-braces guard so this holds even if
-- something re-inserts a machine-authored row later: an activity_log entry
-- attributed to the assistant (or carrying the old 'due' action) is logged
-- to History as before, it just doesn't page anyone's phone.

-- ---------------------------------------------------------------------------
-- 1. Unschedule every notification-producing cron job.
-- ---------------------------------------------------------------------------
do $$
declare
  v_job text;
begin
  foreach v_job in array array[
    'check-due-tasks',
    'check-family-events',
    'check-ai-insights',
    'weekly-ai-digest',
    'ai-personal-checkin',
    'check-shabbat-greeting'
  ] loop
    if exists (select 1 from cron.job where jobname = v_job) then
      perform cron.unschedule(v_job);
    end if;
  end loop;
end $$;

-- The sweeps and the assistant pokes they ran. Dropping them (rather than
-- just unscheduling) means a stray manual `select check_due_tasks();` can't
-- resurrect the behaviour either.
drop function if exists public.check_due_tasks();
drop function if exists public.check_family_events();
drop function if exists public.check_ai_insights();
drop function if exists public.check_ai_weekly_digest();
drop function if exists public.check_ai_personal_checkin();
drop function if exists public.check_ai_shabbat_greeting();

-- Only the (now removed) scheduled intents ever presented this secret —
-- chat is open to anyone with the link, same as the rest of the app.
drop function if exists public.verify_assistant_trigger_secret(text);

-- Kept on purpose: tasks.due_notified_at / family_events.last_notified_on
-- and the tasks_reset_due_notified trigger. They're inert bookkeeping now
-- (nothing reads them), and keeping the columns preserves the history of
-- what was already notified about, so reminders could be switched back on
-- without re-notifying years of past due dates.

-- ---------------------------------------------------------------------------
-- 2. Jessica's own push triggers.
-- ---------------------------------------------------------------------------
drop trigger if exists ai_suggestions_notify_push on public.ai_suggestions;
drop function if exists public.notify_push_ai_suggestion();

drop trigger if exists ai_private_messages_notify_push on public.ai_private_messages;
drop function if exists public.notify_push_ai_private_message();

-- ---------------------------------------------------------------------------
-- 3. notify_push(): human-authored activity only.
--
-- Unattributed rows (actor_id is null) still notify — a human action whose
-- attribution didn't resolve is a real event, and the only writers that
-- deliberately left actor_id null were the sweeps removed above.
-- ---------------------------------------------------------------------------
create or replace function public.notify_push()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_secret text;
  v_assistant_id uuid;
begin
  -- Scheduled/machine-generated entries are recorded in History, never pushed.
  if NEW.action = 'due' then
    return null;
  end if;

  select id into v_assistant_id from public.members where email = 'assistant@kh.family';
  if v_assistant_id is not null and NEW.actor_id = v_assistant_id then
    return null;
  end if;

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

-- ---------------------------------------------------------------------------
-- 4. The per-member switches for the notification kinds that no longer
-- exist. Left in place (rather than dropped) so an already-installed PWA
-- still holding the old client bundle can keep upserting its prefs row
-- without hitting an unknown-column error; nothing reads them any more.
-- ---------------------------------------------------------------------------
comment on column public.notification_prefs.on_due is
  'Inert since 0031 — scheduled due-date reminders were removed.';
comment on column public.notification_prefs.on_ai_personal is
  'Inert since 0031 — the assistant no longer sends unsolicited messages.';

-- Same story for the two columns 0026 added to drive personal check-ins.
-- ai_suggestions and ai_private_messages keep whatever they already hold
-- (a member can still dismiss/read an old card), they just never gain rows.
comment on column public.members.is_ai_companion_target is
  'Inert since 0031 — the assistant no longer sends unsolicited messages.';
comment on column public.members.last_chat_at is
  'Inert since 0031 — only the removed personal check-in ever read it.';

-- ---------------------------------------------------------------------------
-- 5. Deletions are one of the human actions the household explicitly wants
-- to hear about, and until now they were the only kind of change that fell
-- through send-push's action matrix into "notify nobody". Restores ride the
-- same switch — undoing a delete is the same conversation.
-- ---------------------------------------------------------------------------
alter table public.notification_prefs add column if not exists on_delete boolean not null default true;

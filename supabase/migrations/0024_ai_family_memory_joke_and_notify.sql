-- Three assistant follow-ups requested together:
-- 1. Push notifications for new insight/"notes" cards — until now a new
--    ai_suggestions row only ever showed up silently as a dashboard card.
-- 2. A once-a-day joke broadcast, generated and sent by the assistant with
--    zero human involvement (a pure FYI, nothing to "apply").
-- 3. family_facts — a free-text memory the assistant grows on its own (see
--    remember_family_fact in supabase/functions/assistant/index.ts), seeded
--    here with what the household told us directly.
--
-- Also: the assistant is Hebrew-only now (see LANGUAGE_INSTRUCTION in the
-- Edge Function), so the 'locale' field check_ai_insights (0023) used to
-- send is dead weight — redefined below without it.

create or replace function public.check_ai_insights()
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
    body := jsonb_build_object('intent', 'insights')
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Push notification when the assistant creates a new insight card.
-- Mirrors notify_push() (0006) but sourced from ai_suggestions instead of
-- activity_log, since a suggestion never goes through activity_log itself
-- (it's not household state — see 0022's comment on ai_suggestions).
-- ---------------------------------------------------------------------------
create or replace function public.notify_push_ai_suggestion()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
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
      'entity_type', 'ai_suggestion',
      'entity_id', NEW.id,
      'action', 'message',
      'actor_id', v_actor_id,
      'summary', coalesce(NEW.emoji || ' ', '') || NEW.summary,
      'created_at', NEW.created_at
    )
  );

  return null;
end;
$$;

drop trigger if exists ai_suggestions_notify_push on public.ai_suggestions;
create trigger ai_suggestions_notify_push
  after insert on public.ai_suggestions
  for each row execute function public.notify_push_ai_suggestion();

-- ---------------------------------------------------------------------------
-- 2. Daily joke. The cron job just pokes the assistant Edge Function, which
-- decides for itself whether one's already gone out today, then writes
-- straight to activity_log as a 'broadcast'/'message' — the exact same shape
-- a human-confirmed send_broadcast produces — so it rides the existing
-- activity_log -> send-push pipeline with zero new plumbing.
-- ---------------------------------------------------------------------------
create or replace function public.check_ai_daily_joke()
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
    return; -- not configured yet — no-op, same as check_ai_insights()
  end if;

  perform net.http_post(
    url := 'https://ogoxwhebqxjligxeqnqd.functions.supabase.co/assistant',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_secret),
    body := jsonb_build_object('intent', 'joke')
  );
end;
$$;

-- Once a day, morning-ish (UTC — approximate, matches the existing
-- check-ai-insights/check-family-events jobs which don't correct for
-- local time either).
select cron.schedule('daily-ai-joke', '0 7 * * *', $$select public.check_ai_daily_joke();$$);

-- ---------------------------------------------------------------------------
-- 3. Family memory: free-text notes the assistant teaches itself over time.
-- No fixed relationship schema on purpose — this is meant to grow
-- organically via remember_family_fact, not be hand-curated.
-- ---------------------------------------------------------------------------
create table public.family_facts (
  id          uuid primary key default gen_random_uuid(),
  fact        text not null,
  created_at  timestamptz not null default now()
);

alter table public.family_facts enable row level security;

create policy "members full access to family_facts" on public.family_facts
  for all using (public.is_member()) with check (public.is_member());

insert into public.family_facts (fact) values
  ('קורן וחיים הם בני זוג'),
  ('יריב הוא האבא המאמץ של חיים, ויש לו קשר טוב עם קורן, והוא הרבה פעמים עוזר להם עם קניות'),
  ('לואי הוא הכלב האהוב בעולם, ויריב עושה בשבילו הכל');

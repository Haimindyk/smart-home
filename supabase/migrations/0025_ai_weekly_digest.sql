-- Weekly digest: mirrors check_ai_daily_joke() (0024) exactly, just on a
-- weekly cadence and hitting the assistant's new "digest" intent, which
-- summarizes the week ahead (events, due tasks, chores coming due) as a
-- warm, funny broadcast — same personality as the daily joke, per the
-- household's request.

create or replace function public.check_ai_weekly_digest()
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
    return; -- not configured yet — no-op, same as check_ai_insights()/check_ai_daily_joke()
  end if;

  perform net.http_post(
    url := 'https://ogoxwhebqxjligxeqnqd.functions.supabase.co/assistant',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_secret),
    body := jsonb_build_object('intent', 'digest')
  );
end;
$$;

-- Sunday morning, the start of the week for this household.
select cron.schedule('weekly-ai-digest', '0 7 * * 0', $$select public.check_ai_weekly_digest();$$);

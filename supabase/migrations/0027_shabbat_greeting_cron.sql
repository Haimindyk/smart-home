-- Weekly Shabbat Shalom greeting, requested directly by the household: a
-- warm broadcast every Friday at 18:00 Israel time.
--
-- pg_cron schedules are fixed UTC with no DST awareness, and Israel shifts
-- between UTC+2 (winter) and UTC+3 (summer) — so instead of picking one UTC
-- cron time that would only be correct for half the year, this fires every
-- 15 minutes across a window that covers 18:00 Israel time under both
-- offsets (15:00 UTC in summer, 16:00 UTC in winter), and the Edge
-- Function's own isShabbatGreetingTime() check (real Israel local time)
-- decides whether this is actually the moment to send — mirrors how the
-- 9am-midnight notification window works for the other proactive intents.
create or replace function public.check_ai_shabbat_greeting()
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
    body := jsonb_build_object('intent', 'shabbat_greeting')
  );
end;
$$;

select cron.schedule('check-shabbat-greeting', '*/15 15-19 * * 5', $$select public.check_ai_shabbat_greeting();$$);

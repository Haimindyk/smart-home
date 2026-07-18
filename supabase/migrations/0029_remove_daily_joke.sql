-- The household asked to remove the daily joke (added in 0024). Unschedule
-- its cron job and drop the poke function; the assistant Edge Function no
-- longer accepts a 'joke' intent either. The weekly digest, insights,
-- Shabbat greeting, and personal check-ins are unaffected.

do $$
begin
  if exists (select 1 from cron.job where jobname = 'daily-ai-joke') then
    perform cron.unschedule('daily-ai-joke');
  end if;
end $$;

drop function if exists public.check_ai_daily_joke();

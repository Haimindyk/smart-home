-- Keeps public.activity_log capped at the newest 30 rows going forward —
-- the app itself only ever fetches/displays the newest 30 (see
-- use-realtime-sync.ts), so anything older than that was already invisible
-- in the UI; this just stops the table from growing unbounded behind the
-- scenes too. Runs after every insert (every task/section/chore change and
-- broadcast goes through activity_log — see 0004/0005/0009's triggers),
-- trimming down to the 30 most recent by `seq` (the strictly-monotonic
-- identity column, see 0005) each time. A no-op once there are 30 or
-- fewer rows: the subquery returns null, and `seq <= null` never matches.
create or replace function public.trim_activity_log()
returns trigger
language plpgsql
as $$
begin
  delete from public.activity_log
  where seq <= (select seq from public.activity_log order by seq desc offset 30 limit 1);
  return null;
end;
$$;

drop trigger if exists activity_log_trim on public.activity_log;
create trigger activity_log_trim
  after insert on public.activity_log
  for each row execute function public.trim_activity_log();

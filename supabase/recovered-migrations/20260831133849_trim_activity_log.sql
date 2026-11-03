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
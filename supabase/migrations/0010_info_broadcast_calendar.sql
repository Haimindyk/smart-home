-- Three additions requested together:
-- 1. A dedicated "info" section kind (a real place for reference notes —
--    WiFi passwords, phone numbers — instead of a per-item toggle buried in
--    task quick-add).
-- 2. A "broadcast" activity_log entity/action pair so a member can push a
--    free-text message to everyone else's device, reusing the existing
--    activity_log -> send-push pipeline instead of building a new one.
-- 3. A family_events table (birthdays, medical checkups, ...) with the same
--    "due timestamp + notified bookkeeping + periodic sweep" shape as
--    0009's task due-date reminders, extended with yearly recurrence.

-- ---------------------------------------------------------------------------
-- 1. Info section kind
-- ---------------------------------------------------------------------------
alter table public.sections drop constraint if exists sections_kind_check;
alter table public.sections add constraint sections_kind_check
  check (kind in ('tasks', 'shopping', 'chores', 'info'));

-- ---------------------------------------------------------------------------
-- 2. Broadcast messages
-- ---------------------------------------------------------------------------
alter table public.activity_log drop constraint if exists activity_log_entity_type_check;
alter table public.activity_log add constraint activity_log_entity_type_check
  check (entity_type = any (array['section', 'task', 'chore', 'broadcast', 'family_event']));

alter table public.activity_log drop constraint if exists activity_log_action_check;
alter table public.activity_log add constraint activity_log_action_check
  check (action = any (array['created','updated','completed','uncompleted','deleted','restored','moved','renamed','due','message']));

alter table public.notification_prefs add column if not exists on_broadcast boolean not null default true;

-- ---------------------------------------------------------------------------
-- 3. Family events calendar
-- ---------------------------------------------------------------------------
create table public.family_events (
  id              uuid primary key default gen_random_uuid(),
  title           text not null,
  kind            text not null default 'other' check (kind in ('birthday', 'medical', 'other')),
  emoji           text,
  event_date      date not null,
  recurrence      text not null default 'none' check (recurrence in ('none', 'yearly')),
  notes           text,
  last_notified_on date,
  created_by      uuid references public.members(id) on delete set null,
  updated_by      uuid references public.members(id) on delete set null,
  deleted_at      timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index family_events_event_date_idx on public.family_events (event_date) where deleted_at is null;

create trigger family_events_set_updated_at
  before update on public.family_events
  for each row execute function public.set_updated_at();

alter table public.family_events enable row level security;

create policy "members full access to family_events" on public.family_events
  for all using (public.is_member()) with check (public.is_member());

alter publication supabase_realtime add table public.family_events;

-- Next real-world occurrence of an event on/after `p_as_of`. One-off events
-- return their fixed date; yearly ones roll the month/day forward to the
-- current (or next) year. Feb 29 anchors that fall in a non-leap year land
-- on Feb 28 rather than raising.
create or replace function public.family_event_next_occurrence(p_event_date date, p_recurrence text, p_as_of date default current_date)
returns date
language plpgsql
immutable
as $$
declare
  v_month int := extract(month from p_event_date)::int;
  v_day   int := extract(day from p_event_date)::int;
  v_year  int := extract(year from p_as_of)::int;
  v_candidate date;
begin
  if p_recurrence <> 'yearly' then
    return p_event_date;
  end if;

  loop
    begin
      v_candidate := make_date(v_year, v_month, v_day);
      exit;
    exception when others then
      v_day := v_day - 1; -- Feb 29 in a non-leap year -> Feb 28
    end;
  end loop;

  if v_candidate < p_as_of then
    v_year := v_year + 1;
    v_day := extract(day from p_event_date)::int;
    loop
      begin
        v_candidate := make_date(v_year, v_month, v_day);
        exit;
      exception when others then
        v_day := v_day - 1;
      end;
    end loop;
  end if;

  return v_candidate;
end;
$$;

-- Periodic sweep (mirrors check_due_tasks in 0009): log a 'due' activity_log
-- entry for every event whose next occurrence has arrived today and that
-- hasn't already been notified about today, then stamp last_notified_on so
-- it doesn't repeat until its next real occurrence.
create or replace function public.check_family_events()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.activity_log (entity_type, entity_id, action, actor_id, summary)
  select 'family_event', e.id, 'due', null, coalesce(e.emoji || ' ', '') || e.title
  from public.family_events e
  where e.deleted_at is null
    and public.family_event_next_occurrence(e.event_date, e.recurrence) = current_date
    and (e.last_notified_on is null or e.last_notified_on <> current_date);

  update public.family_events e
  set last_notified_on = current_date
  where e.deleted_at is null
    and public.family_event_next_occurrence(e.event_date, e.recurrence) = current_date
    and (e.last_notified_on is null or e.last_notified_on <> current_date);
end;
$$;

select cron.schedule('check-family-events', '*/10 * * * *', $$select public.check_family_events();$$);

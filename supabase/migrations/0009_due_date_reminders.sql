-- Push notification when a task's due date arrives. Reuses the existing
-- activity_log -> send-push pipeline: a scheduled job inserts a 'due'
-- activity_log row for each newly-due task, and the trigger already wired
-- in 0006 fans that out to subscribed devices exactly like any other event.

-- ---------------------------------------------------------------------------
-- Track whether a task has already gotten its due-date reminder, so the
-- periodic check doesn't re-notify on every run.
-- ---------------------------------------------------------------------------
alter table public.tasks add column if not exists due_notified_at timestamptz;

-- Don't blast a first-run notification storm for tasks that were already
-- overdue before this feature existed — treat existing overdue items as
-- already-handled; only newly-arriving due dates from here on get a push.
update public.tasks
set due_notified_at = now()
where due_at is not null and due_at <= now() and due_notified_at is null;

-- If a due date is edited (e.g. postponed), the task should be eligible for
-- a fresh reminder when the new date arrives.
create or replace function public.reset_due_notified()
returns trigger
language plpgsql
as $$
begin
  if new.due_at is distinct from old.due_at then
    new.due_notified_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists tasks_reset_due_notified on public.tasks;
create trigger tasks_reset_due_notified
  before update on public.tasks
  for each row execute function public.reset_due_notified();

-- ---------------------------------------------------------------------------
-- 'due' joins the set of activity_log actions the push pipeline understands.
-- ---------------------------------------------------------------------------
alter table public.activity_log drop constraint if exists activity_log_action_check;
alter table public.activity_log add constraint activity_log_action_check
  check (action = any (array['created','updated','completed','uncompleted','deleted','restored','moved','renamed','due']));

-- Per-member opt-out for due-date reminders specifically (separate from
-- on_assigned_me — being assigned and a thing you're assigned to becoming
-- due are different signals worth muting independently).
alter table public.notification_prefs add column if not exists on_due boolean not null default true;

-- ---------------------------------------------------------------------------
-- The periodic check: log (and fan out via the existing trigger) a 'due'
-- activity_log row for every task whose due date has arrived and hasn't
-- been notified about yet.
-- ---------------------------------------------------------------------------
create or replace function public.check_due_tasks()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.activity_log (entity_type, entity_id, action, actor_id, summary)
  select 'task', t.id, 'due', null, t.title
  from public.tasks t
  where t.due_at is not null
    and t.due_at <= now()
    and t.due_notified_at is null
    and t.deleted_at is null
    and t.is_completed = false
    and t.is_note = false;

  update public.tasks
  set due_notified_at = now()
  where due_at is not null
    and due_at <= now()
    and due_notified_at is null
    and deleted_at is null
    and is_completed = false
    and is_note = false;
end;
$$;

create extension if not exists pg_cron;

select cron.schedule('check-due-tasks', '*/10 * * * *', $$select public.check_due_tasks();$$);

-- ---------------------------------------------------------------------------
-- Stamping due_notified_at is bookkeeping, not a user-meaningful edit — the
-- generic activity logger (0004) would otherwise log a redundant "updated"
-- entry every time a due reminder fires, right alongside the "due" entry
-- check_due_tasks() already logs for the same task.
-- ---------------------------------------------------------------------------
create or replace function public.log_activity()
returns trigger
language plpgsql
as $$
declare
  v_entity_type text;
  v_action      text;
  v_actor       uuid;
  v_summary     text;
  v_id          uuid;
  v_new         jsonb;
  v_old         jsonb;
begin
  v_entity_type := case TG_TABLE_NAME
    when 'tasks' then 'task'
    when 'sections' then 'section'
    when 'chores' then 'chore'
  end;

  v_new := to_jsonb(NEW);
  v_id := (v_new ->> 'id')::uuid;
  v_summary := coalesce(v_new ->> 'title', v_new ->> 'name');
  v_actor := coalesce(
    nullif(v_new ->> 'updated_by', '')::uuid,
    nullif(v_new ->> 'completed_by', '')::uuid,
    nullif(v_new ->> 'created_by', '')::uuid
  );

  if TG_OP = 'INSERT' then
    v_action := 'created';
  elsif TG_OP = 'UPDATE' then
    v_old := to_jsonb(OLD);
    if (v_old - 'due_notified_at' - 'updated_at') = (v_new - 'due_notified_at' - 'updated_at') then
      -- Only internal bookkeeping fields changed — not user-meaningful, skip.
      return null;
    elsif (v_old ? 'is_completed') and (v_old ->> 'is_completed') is distinct from (v_new ->> 'is_completed') then
      v_action := case when (v_new ->> 'is_completed')::boolean then 'completed' else 'uncompleted' end;
    elsif (v_old ->> 'deleted_at') is distinct from (v_new ->> 'deleted_at') then
      v_action := case when v_new ->> 'deleted_at' is not null then 'deleted' else 'restored' end;
    elsif (v_old ->> 'title') is distinct from (v_new ->> 'title')
       or (v_old ->> 'name') is distinct from (v_new ->> 'name') then
      v_action := 'renamed';
    else
      v_action := 'updated';
    end if;
  else
    return null;
  end if;

  insert into public.activity_log (entity_type, entity_id, action, actor_id, summary)
  values (v_entity_type, v_id, v_action, v_actor, v_summary);

  return null;
end;
$$;

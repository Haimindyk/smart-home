-- PIN-based identification (client-side gate, not real auth — see README's
-- "Access model" section) + a real change-history log populated by triggers
-- so "who changed what, when" doesn't depend on every call site remembering
-- to write to activity_log by hand.

-- ---------------------------------------------------------------------------
-- Members: add a PIN + Yariv
-- ---------------------------------------------------------------------------
alter table public.members add column if not exists pin text;

update public.members set pin = '1011' where email = 'haim_indyk@icloud.com';
update public.members set pin = '0305' where email = 'Koren8761@gmail.com';

-- yariv@kh.family is a placeholder unique key, not a real contact address —
-- this app has no email-based auth, `email` is just an identity row key.
insert into public.members (email, display_name, avatar_emoji, color, pin) values
  ('yariv@kh.family', 'יריב', '🙂', '#a855f7', '0711')
on conflict (email) do update set pin = excluded.pin;

-- ---------------------------------------------------------------------------
-- Actor tracking columns (so the trigger below knows who to attribute)
-- ---------------------------------------------------------------------------
alter table public.tasks add column if not exists updated_by uuid references public.members(id) on delete set null;
alter table public.sections add column if not exists updated_by uuid references public.members(id) on delete set null;
alter table public.chores add column if not exists updated_by uuid references public.members(id) on delete set null;
alter table public.chores add column if not exists created_by uuid references public.members(id) on delete set null;

-- ---------------------------------------------------------------------------
-- Generic activity logger, attached to tasks/sections/chores
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
    if (v_old ? 'is_completed') and (v_old ->> 'is_completed') is distinct from (v_new ->> 'is_completed') then
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

drop trigger if exists tasks_log_activity on public.tasks;
create trigger tasks_log_activity
  after insert or update on public.tasks
  for each row execute function public.log_activity();

drop trigger if exists sections_log_activity on public.sections;
create trigger sections_log_activity
  after insert or update on public.sections
  for each row execute function public.log_activity();

drop trigger if exists chores_log_activity on public.chores;
create trigger chores_log_activity
  after insert or update on public.chores
  for each row execute function public.log_activity();

-- ---------------------------------------------------------------------------
-- Thread the actor through the RPCs that write on the client's behalf
-- ---------------------------------------------------------------------------
create or replace function public.soft_delete_task(p_task_id uuid, p_actor_id uuid default null)
returns void
language plpgsql
security invoker
as $$
declare
  ts timestamptz := now();
begin
  with recursive subtree as (
    select id from public.tasks where id = p_task_id
    union all
    select t.id from public.tasks t join subtree s on t.parent_task_id = s.id
  )
  update public.tasks set deleted_at = ts, updated_by = p_actor_id
  where id in (select id from subtree) and deleted_at is null;
end;
$$;

create or replace function public.restore_task(p_task_id uuid, p_actor_id uuid default null)
returns void
language plpgsql
security invoker
as $$
declare
  ts0 timestamptz;
begin
  select deleted_at into ts0 from public.tasks where id = p_task_id;
  if ts0 is null then
    return;
  end if;

  with recursive subtree as (
    select id from public.tasks where id = p_task_id
    union all
    select t.id from public.tasks t join subtree s on t.parent_task_id = s.id
  )
  update public.tasks set deleted_at = null, updated_by = p_actor_id
  where id in (select id from subtree) and deleted_at = ts0;
end;
$$;

create or replace function public.complete_chore(p_chore_id uuid, p_completed_by uuid)
returns void
language plpgsql
security invoker
as $$
declare
  c record;
  new_due timestamptz;
  d date;
  found_day date;
begin
  select * into c from public.chores where id = p_chore_id for update;
  if not found then
    raise exception 'chore % not found', p_chore_id;
  end if;

  insert into public.chore_completions (chore_id, completed_by, due_at)
  values (p_chore_id, p_completed_by, c.next_due_at);

  if c.freq = 'daily' then
    new_due := c.next_due_at + make_interval(days => c.interval_n);
  elsif c.freq = 'weekly' and c.weekdays is not null and array_length(c.weekdays, 1) > 0 then
    d := (c.next_due_at::date) + 1;
    found_day := null;
    for i in 0..13 loop
      if extract(dow from d)::int = any(c.weekdays) then
        found_day := d;
        exit;
      end if;
      d := d + 1;
    end loop;
    new_due := coalesce(found_day, (c.next_due_at::date) + 7)::timestamptz
               + (c.next_due_at - c.next_due_at::date);
  elsif c.freq = 'weekly' then
    new_due := c.next_due_at + make_interval(weeks => c.interval_n);
  elsif c.freq = 'monthly' then
    new_due := c.next_due_at + make_interval(months => c.interval_n);
  else
    new_due := now();
  end if;

  update public.chores set next_due_at = new_due, updated_by = p_completed_by where id = p_chore_id;
end;
$$;

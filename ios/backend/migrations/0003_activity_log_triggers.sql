-- Populate activity_log automatically for the two events people actually
-- want a history of: task lifecycle (created/completed/uncompleted/deleted)
-- and chore completions. This mirrors the website's activity_log, scoped
-- down to what a lightweight iOS "recent activity" screen needs — a full
-- browsable audit UI (like the website's own deferred item) stays out of
-- scope here too.

create or replace function public.log_task_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.activity_log (area_id, entity_type, entity_id, action, actor_id, summary)
    values (new.area_id, 'task', new.id, 'created', new.created_by, new.title);
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if new.deleted_at is not null and old.deleted_at is null then
      insert into public.activity_log (area_id, entity_type, entity_id, action, actor_id, summary)
      values (new.area_id, 'task', new.id, 'deleted', new.updated_by, new.title);
    elsif new.is_completed and not old.is_completed then
      insert into public.activity_log (area_id, entity_type, entity_id, action, actor_id, summary)
      values (new.area_id, 'task', new.id, 'completed', new.completed_by, new.title);
    elsif old.is_completed and not new.is_completed then
      insert into public.activity_log (area_id, entity_type, entity_id, action, actor_id, summary)
      values (new.area_id, 'task', new.id, 'uncompleted', new.updated_by, new.title);
    end if;
    return new;
  end if;

  return new;
end;
$$;

create trigger tasks_log_activity
  after insert or update on public.tasks
  for each row execute function public.log_task_activity();

create or replace function public.log_chore_completion_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
begin
  select title into v_title from public.chores where id = new.chore_id;
  insert into public.activity_log (area_id, entity_type, entity_id, action, actor_id, summary)
  values (new.area_id, 'chore', new.chore_id, 'completed', new.completed_by, v_title);
  return new;
end;
$$;

create trigger chore_completions_log_activity
  after insert on public.chore_completions
  for each row execute function public.log_chore_completion_activity();

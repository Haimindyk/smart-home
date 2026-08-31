-- 0034 made a board's tasks/sections/chores skip activity_log entirely (to
-- avoid leaking them into the household-wide History/push), which also
-- meant a board never got its own history at all, and the flat trim added
-- afterward (0035) capped the newest 30 rows *across the whole household*
-- instead of 30 per board — a board sharing that global pool could get
-- starved out by main-house activity, or vice versa.
--
-- This migration gives activity_log a board_id (same nullable pattern as
-- sections), makes its RLS board-aware so a board's rows are only visible
-- to its own members, and centralizes the "never push board activity to
-- the whole household" rule in notify_push() itself — so every writer
-- (log_activity, log_chore_completion, check_due_tasks) can go back to
-- unconditionally logging, tagged with whichever board (if any) it
-- belongs to, instead of each one separately deciding to skip.

alter table public.activity_log add column if not exists board_id uuid references public.boards(id) on delete cascade;
create index if not exists activity_log_board_idx on public.activity_log (board_id) where board_id is not null;

drop policy if exists "members full access to activity_log" on public.activity_log;
create policy "board-aware access to activity_log" on public.activity_log
  for all using (public.can_access_board(board_id)) with check (public.can_access_board(board_id));

-- ---------------------------------------------------------------------------
-- log_activity() (0004, last touched by 0034): stamp board_id instead of
-- skipping the insert for board-scoped rows.
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
  v_board_id    uuid;
begin
  v_entity_type := case TG_TABLE_NAME
    when 'tasks' then 'task'
    when 'sections' then 'section'
    when 'chores' then 'chore'
  end;

  v_new := to_jsonb(NEW);
  v_id := (v_new ->> 'id')::uuid;

  if TG_TABLE_NAME = 'sections' then
    v_board_id := (v_new ->> 'board_id')::uuid;
  else
    select board_id into v_board_id from public.sections where id = (v_new ->> 'section_id')::uuid;
  end if;

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

  insert into public.activity_log (entity_type, entity_id, action, actor_id, summary, board_id)
  values (v_entity_type, v_id, v_action, v_actor, v_summary, v_board_id);

  return null;
end;
$$;

create or replace function public.log_chore_completion()
returns trigger
language plpgsql
as $$
declare
  v_title    text;
  v_board_id uuid;
begin
  select c.title, s.board_id into v_title, v_board_id
  from public.chores c
  join public.sections s on s.id = c.section_id
  where c.id = NEW.chore_id;

  insert into public.activity_log (entity_type, entity_id, action, actor_id, summary, board_id)
  values ('chore', NEW.chore_id, 'completed', NEW.completed_by, v_title, v_board_id);
  return null;
end;
$$;

-- check_due_tasks() (0009, last touched by 0034): due reminders now log to
-- a board's own history too — still never pushed (see notify_push() below).
create or replace function public.check_due_tasks()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.activity_log (entity_type, entity_id, action, actor_id, summary, board_id)
  select 'task', t.id, 'due', null, t.title, s.board_id
  from public.tasks t
  join public.sections s on s.id = t.section_id
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

-- ---------------------------------------------------------------------------
-- notify_push() (0006): the one place that now decides "does this activity
-- reach the whole household" — board-scoped rows never do (a board-aware
-- push fan-out, notifying just that board's members, is a separate
-- project; for now a board simply gets in-app history, no push).
-- ---------------------------------------------------------------------------
create or replace function public.notify_push()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_secret text;
begin
  if NEW.board_id is not null then
    return null;
  end if;

  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'push_trigger_secret';

  if v_secret is null then
    return null;
  end if;

  perform net.http_post(
    url := 'https://ogoxwhebqxjligxeqnqd.functions.supabase.co/send-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_secret),
    body := to_jsonb(NEW)
  );

  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- trim_activity_log() (0035): rank and trim *within each board* (NULL board
-- — the shared household — counts as its own partition), not across the
-- whole table, so one busy board can't starve another's history down to
-- nothing.
-- ---------------------------------------------------------------------------
create or replace function public.trim_activity_log()
returns trigger
language plpgsql
as $$
begin
  delete from public.activity_log al
  using (
    select id, row_number() over (partition by board_id order by seq desc) as rn
    from public.activity_log
  ) ranked
  where al.id = ranked.id and ranked.rn > 30;
  return null;
end;
$$;

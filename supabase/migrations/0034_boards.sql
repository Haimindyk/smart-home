-- Private boards: a completely separate mini-house (its own sections/tasks/
-- chores) that a member creates with whichever other members they choose —
-- invisible in existence, not just content, to everyone else in the
-- household. Reuses the existing sections/tasks/chores tables (via a new
-- nullable `board_id` on sections) rather than a parallel schema, so every
-- existing UI component (SectionPanels, task rows, etc.) keeps working
-- unchanged for a board's own view.
--
-- SAFETY: this migration is written so that every existing row (board_id is
-- null, since the column is new) behaves *exactly* as before — every
-- rewritten policy below routes the "no board" case through the same
-- public.is_member() the old policy already used, verbatim. Only rows that
-- explicitly opt into a board get the new, stricter check. Nothing here
-- touches is_member() itself or any other table.
--
-- Requires migration 0033 (current_member_id(), i.e. a real per-member auth
-- session minted by supabase/functions/pin-login) to mean anything — a
-- request with no such session simply never matches any board, same as any
-- other non-member.

create table public.boards (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  emoji       text,
  created_by  uuid references public.members(id) on delete set null,
  created_at  timestamptz not null default now()
);

-- `id` as its own surrogate primary key (rather than a composite
-- board_id+member_id PK) so this fits the app's existing generic realtime
-- sync plumbing (src/lib/realtime/use-realtime-sync.ts), which keys every
-- table's rows by a single `id` column — the (board_id, member_id) unique
-- constraint below still does the actual "no duplicate membership" work.
create table public.board_members (
  id          uuid primary key default gen_random_uuid(),
  board_id    uuid not null references public.boards(id) on delete cascade,
  member_id   uuid not null references public.members(id) on delete cascade,
  added_at    timestamptz not null default now(),
  unique (board_id, member_id)
);

alter table public.sections add column if not exists board_id uuid references public.boards(id) on delete cascade;
create index if not exists sections_board_idx on public.sections (board_id) where board_id is not null;

-- ---------------------------------------------------------------------------
-- Access helpers — every one SECURITY DEFINER + STABLE, the standard way to
-- use a table lookup inside another table's RLS policy without either
-- infinite self-recursion (board_members' own policy calling back into
-- board_members) or leaking board_members' row contents to non-members via
-- policy evaluation.
-- ---------------------------------------------------------------------------
create or replace function public.can_access_board(p_board_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_board_id is null then public.is_member()
    else exists (
      select 1 from public.board_members
      where board_id = p_board_id and member_id = public.current_member_id()
    )
  end;
$$;

create or replace function public.can_access_section(p_section_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_access_board((select board_id from public.sections where id = p_section_id));
$$;

create or replace function public.can_access_chore(p_chore_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_access_section((select section_id from public.chores where id = p_chore_id));
$$;

-- ---------------------------------------------------------------------------
-- boards / board_members RLS — deliberately no insert/update/delete policy
-- on either table (default deny): membership changes only ever happen
-- through create_board() below (security definer, its own authorization
-- check), so there's exactly one audited path that can ever grant access to
-- a board, never a direct table write from the client.
-- ---------------------------------------------------------------------------
alter table public.boards enable row level security;
create policy "board members can view their boards" on public.boards
  for select using (public.can_access_board(id));

alter table public.board_members enable row level security;
create policy "board members can view their board's membership" on public.board_members
  for select using (public.can_access_board(board_id));

create or replace function public.create_board(p_name text, p_emoji text default null, p_member_ids uuid[] default '{}')
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_board_id uuid;
  v_creator  uuid := public.current_member_id();
begin
  if v_creator is null then
    raise exception 'not signed in';
  end if;
  if coalesce(trim(p_name), '') = '' then
    raise exception 'board name is required';
  end if;

  insert into public.boards (name, emoji, created_by) values (trim(p_name), p_emoji, v_creator)
  returning id into v_board_id;

  insert into public.board_members (board_id, member_id)
  select v_board_id, m from unnest(array_append(p_member_ids, v_creator)) as m
  on conflict do nothing;

  return v_board_id;
end;
$$;

revoke all on function public.create_board(text, text, uuid[]) from public, anon;
grant execute on function public.create_board(text, text, uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- sections/tasks/chores/chore_completions: replace the old blanket
-- is_member() policy with the board-aware equivalent. For every existing
-- row (board_id null) this is exactly the same predicate as before.
-- ---------------------------------------------------------------------------
drop policy if exists "members full access to sections" on public.sections;
create policy "board-aware access to sections" on public.sections
  for all using (public.can_access_board(board_id)) with check (public.can_access_board(board_id));

drop policy if exists "members full access to tasks" on public.tasks;
create policy "board-aware access to tasks" on public.tasks
  for all using (public.can_access_section(section_id)) with check (public.can_access_section(section_id));

drop policy if exists "members full access to chores" on public.chores;
create policy "board-aware access to chores" on public.chores
  for all using (public.can_access_section(section_id)) with check (public.can_access_section(section_id));

drop policy if exists "members full access to chore_completions" on public.chore_completions;
create policy "board-aware access to chore_completions" on public.chore_completions
  for all using (public.can_access_chore(chore_id)) with check (public.can_access_chore(chore_id));

-- ---------------------------------------------------------------------------
-- log_activity()/log_chore_completion() (0004/0005) write into the fully
-- open, household-wide activity_log — visible in History and fanned out to
-- everyone via push (send-push) — unconditionally today. A board-scoped
-- row must never reach it, or a "private" board's task titles would leak
-- to the whole household the moment anyone touches them. These triggers
-- run in a context RLS doesn't gate (see migration comments elsewhere in
-- this codebase re: security invoker vs definer), so the skip has to be
-- explicit here rather than inherited from a policy.
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
  if v_board_id is not null then
    return null;
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

  insert into public.activity_log (entity_type, entity_id, action, actor_id, summary)
  values (v_entity_type, v_id, v_action, v_actor, v_summary);

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

  if v_board_id is not null then
    return null;
  end if;

  insert into public.activity_log (entity_type, entity_id, action, actor_id, summary)
  values ('chore', NEW.chore_id, 'completed', NEW.completed_by, v_title);
  return null;
end;
$$;

-- check_due_tasks() (0009) runs on a schedule as a privileged role, not
-- through a member's own RLS-scoped request — same reasoning as above,
-- needs its own explicit exclusion. Board tasks simply don't get a due-date
-- push in this version (a board-aware push fan-out is a separate project).
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
  join public.sections s on s.id = t.section_id
  where t.due_at is not null
    and t.due_at <= now()
    and t.due_notified_at is null
    and t.deleted_at is null
    and t.is_completed = false
    and t.is_note = false
    and s.board_id is null;

  update public.tasks
  set due_notified_at = now()
  where due_at is not null
    and due_at <= now()
    and due_notified_at is null
    and deleted_at is null
    and is_completed = false
    and is_note = false
    and section_id in (select id from public.sections where board_id is null);
end;
$$;

alter publication supabase_realtime add table public.boards;
alter publication supabase_realtime add table public.board_members;

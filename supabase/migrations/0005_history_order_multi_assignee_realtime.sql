-- Three independent fixes bundled in one migration since they touch adjacent
-- schema and were planned together:
--   1. activity_log gets a strictly-monotonic `seq` so History can be sorted
--      correctly even when several rows share the same transaction-time
--      `created_at` (e.g. soft-deleting a whole task subtree at once).
--   2. chores/tasks gain a multi-member assignee array (the single
--      assignee_member_id model can't express "assigned to both Koren and
--      Yariv"), plus a completions->activity_log trigger so "who actually
--      completed a chore" shows up in history as its own entry.
--   3. `members` joins the realtime publication (it was the only
--      collaborative table missing from it, so profile edits never synced
--      live) and chore_completions gets its own trigger without needing a
--      new publication entry (it's already published).

-- ---------------------------------------------------------------------------
-- 1. Stable ordering for activity_log
-- ---------------------------------------------------------------------------
alter table public.activity_log add column if not exists seq bigint generated always as identity;
create index if not exists activity_log_seq_idx on public.activity_log (seq desc);

-- ---------------------------------------------------------------------------
-- 2. Multi-member assignees for chores + tasks
-- ---------------------------------------------------------------------------
alter table public.chores add column if not exists assignee_member_ids uuid[] not null default '{}';
alter table public.tasks add column if not exists assignee_member_ids uuid[] not null default '{}';

update public.chores set assignee_member_ids = array[assignee_member_id]
  where assignee_member_id is not null and assignee_member_ids = '{}';
update public.tasks set assignee_member_ids = array[assignee_member_id]
  where assignee_member_id is not null and assignee_member_ids = '{}';

-- The old constraint required exactly one assignee when assignee_kind = 'member';
-- assignee_member_ids now allows any number, so it's no longer a valid invariant.
alter table public.chores drop constraint if exists assignee_shape;
alter table public.tasks drop constraint if exists assignee_shape;

-- Log chore completions as their own "completed" activity row (previously a
-- completion only showed up as a `chores` UPDATE, i.e. action='updated').
create or replace function public.log_chore_completion()
returns trigger
language plpgsql
as $$
declare
  v_title text;
begin
  select title into v_title from public.chores where id = NEW.chore_id;
  insert into public.activity_log (entity_type, entity_id, action, actor_id, summary)
  values ('chore', NEW.chore_id, 'completed', NEW.completed_by, v_title);
  return null;
end;
$$;

drop trigger if exists chore_completions_log_activity on public.chore_completions;
create trigger chore_completions_log_activity
  after insert on public.chore_completions
  for each row execute function public.log_chore_completion();

-- ---------------------------------------------------------------------------
-- 3. members was the one collaborative table missing from realtime
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table public.members;

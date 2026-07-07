-- K&H family workspace: core schema
-- Single implicit workspace: authorization is "is your email in `members`", so
-- no workspace_id column is needed anywhere (see design doc in PR description).

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- updated_at trigger helper
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- members: the allowlist. Only these emails may ever authenticate meaningfully.
-- ---------------------------------------------------------------------------
create table public.members (
  id            uuid primary key default gen_random_uuid(),
  email         text not null unique,
  user_id       uuid unique references auth.users(id) on delete set null,
  display_name  text not null,
  avatar_emoji  text,
  color         text not null default '#6366f1',
  locale        text not null default 'he' check (locale in ('he', 'en')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create trigger members_set_updated_at
  before update on public.members
  for each row execute function public.set_updated_at();

-- Link a member row to its auth.users row the first time that email signs in.
create or replace function public.link_member_on_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.members
    set user_id = new.id
    where lower(email) = lower(new.email) and user_id is null;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.link_member_on_signup();

-- ---------------------------------------------------------------------------
-- is_member(): the single RLS predicate used on every table
-- ---------------------------------------------------------------------------
create or replace function public.is_member()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.members
    where user_id = auth.uid()
      and lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

alter table public.members enable row level security;

create policy "members are readable by members" on public.members
  for select using (public.is_member());

create policy "members can update their own row" on public.members
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- sections
-- ---------------------------------------------------------------------------
create table public.sections (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  emoji        text,
  kind         text not null default 'tasks' check (kind in ('tasks', 'shopping', 'chores')),
  color        text,
  description  text,
  position     text not null,
  deleted_at   timestamptz,
  created_by   uuid references public.members(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index sections_position_idx on public.sections (position) where deleted_at is null;

create trigger sections_set_updated_at
  before update on public.sections
  for each row execute function public.set_updated_at();

alter table public.sections enable row level security;

create policy "members full access to sections" on public.sections
  for all using (public.is_member()) with check (public.is_member());

-- ---------------------------------------------------------------------------
-- tasks: unified tasks + subtasks (adjacency list) + shopping items
-- ---------------------------------------------------------------------------
create table public.tasks (
  id              uuid primary key default gen_random_uuid(),
  section_id      uuid not null references public.sections(id) on delete cascade,
  parent_task_id  uuid references public.tasks(id) on delete cascade,
  position        text not null,

  title           text not null default '',
  notes           text,
  emoji           text,
  priority        smallint check (priority between 0 and 3),
  due_at          timestamptz,
  recurrence      jsonb,
  tags            text[] not null default '{}',
  detected_links  text[] not null default '{}',
  is_note         boolean not null default false,

  assignee_member_id uuid references public.members(id) on delete set null,
  assignee_kind      text not null default 'unassigned'
                     check (assignee_kind in ('unassigned', 'member', 'anyone', 'louis')),

  is_completed    boolean not null default false,
  completed_at    timestamptz,
  completed_by    uuid references public.members(id) on delete set null,

  -- shopping-flavored fields (nullable, ignored outside shopping-kind sections)
  quantity        numeric,
  unit            text,
  price           numeric(10, 2),
  currency        text default 'ILS',
  brand           text,
  image_url       text,

  deleted_at      timestamptz,
  created_by      uuid references public.members(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint assignee_shape check ((assignee_kind = 'member') = (assignee_member_id is not null)),
  constraint completed_shape check (is_completed = (completed_at is not null))
);

create index tasks_section_parent_position_idx
  on public.tasks (section_id, parent_task_id, position) where deleted_at is null;
create index tasks_parent_idx on public.tasks (parent_task_id) where deleted_at is null;
create index tasks_due_idx on public.tasks (due_at) where deleted_at is null and is_completed = false;
create index tasks_tags_idx on public.tasks using gin (tags);

create trigger tasks_set_updated_at
  before update on public.tasks
  for each row execute function public.set_updated_at();

alter table public.tasks enable row level security;

create policy "members full access to tasks" on public.tasks
  for all using (public.is_member()) with check (public.is_member());

-- Auto-extract http(s) URLs from title/notes into detected_links on write.
create or replace function public.extract_links()
returns trigger
language plpgsql
as $$
begin
  new.detected_links := coalesce(
    (
      select array_agg(distinct m[1])
      from regexp_matches(coalesce(new.title, '') || ' ' || coalesce(new.notes, ''), 'https?://[^\s]+', 'g') as m
    ),
    '{}'
  );
  return new;
end;
$$;

create trigger tasks_extract_links
  before insert or update of title, notes on public.tasks
  for each row execute function public.extract_links();

-- Cascading soft-delete / restore for a task and its whole subtask subtree.
create or replace function public.soft_delete_task(p_task_id uuid)
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
  update public.tasks set deleted_at = ts
  where id in (select id from subtree) and deleted_at is null;
end;
$$;

create or replace function public.restore_task(p_task_id uuid)
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
  update public.tasks set deleted_at = null
  where id in (select id from subtree) and deleted_at = ts0;
end;
$$;

-- ---------------------------------------------------------------------------
-- chores: recurring rule + append-only completion history
-- ---------------------------------------------------------------------------
create table public.chores (
  id                 uuid primary key default gen_random_uuid(),
  section_id         uuid not null references public.sections(id) on delete cascade,
  title              text not null,
  notes              text,
  emoji              text,
  position           text not null,

  assignee_member_id uuid references public.members(id) on delete set null,
  assignee_kind      text not null default 'anyone'
                     check (assignee_kind in ('member', 'anyone', 'louis')),

  freq               text not null check (freq in ('daily', 'weekly', 'monthly', 'custom', 'as_needed')),
  interval_n         int not null default 1,
  weekdays           int[],
  month_day          int,
  custom_cron        text,
  anchor_date        date not null default current_date,
  next_due_at        timestamptz not null default now(),

  deleted_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),

  constraint assignee_shape check ((assignee_kind = 'member') = (assignee_member_id is not null))
);

create index chores_next_due_idx on public.chores (next_due_at) where deleted_at is null;

create trigger chores_set_updated_at
  before update on public.chores
  for each row execute function public.set_updated_at();

alter table public.chores enable row level security;

create policy "members full access to chores" on public.chores
  for all using (public.is_member()) with check (public.is_member());

create table public.chore_completions (
  id            uuid primary key default gen_random_uuid(),
  chore_id      uuid not null references public.chores(id) on delete cascade,
  completed_by  uuid not null references public.members(id) on delete cascade,
  completed_at  timestamptz not null default now(),
  due_at        timestamptz not null,
  created_at    timestamptz not null default now()
);

create index chore_completions_chore_idx on public.chore_completions (chore_id, completed_at desc);

alter table public.chore_completions enable row level security;

create policy "members full access to chore_completions" on public.chore_completions
  for all using (public.is_member()) with check (public.is_member());

-- Records a completion and advances next_due_at based on the recurrence rule.
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
    -- 'custom' / 'as_needed': no auto-recurrence, stays due immediately again
    new_due := now();
  end if;

  update public.chores set next_due_at = new_due where id = p_chore_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- attachments
-- ---------------------------------------------------------------------------
create table public.attachments (
  id            uuid primary key default gen_random_uuid(),
  task_id       uuid references public.tasks(id) on delete cascade,
  chore_id      uuid references public.chores(id) on delete cascade,
  storage_path  text not null,
  file_name     text not null,
  mime_type     text,
  size_bytes    bigint,
  kind          text not null default 'file' check (kind in ('image', 'pdf', 'audio', 'video', 'file')),
  width         int,
  height        int,
  created_by    uuid references public.members(id) on delete set null,
  created_at    timestamptz not null default now(),

  constraint one_parent check (num_nonnulls(task_id, chore_id) = 1)
);

create index attachments_task_idx on public.attachments (task_id);
create index attachments_chore_idx on public.attachments (chore_id);

alter table public.attachments enable row level security;

create policy "members full access to attachments" on public.attachments
  for all using (public.is_member()) with check (public.is_member());

-- ---------------------------------------------------------------------------
-- Storage bucket for attachments (private; access via signed URLs only)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('attachments', 'attachments', false)
on conflict (id) do nothing;

create policy "members read attachments bucket" on storage.objects
  for select using (bucket_id = 'attachments' and public.is_member());

create policy "members write attachments bucket" on storage.objects
  for insert with check (bucket_id = 'attachments' and public.is_member());

create policy "members update attachments bucket" on storage.objects
  for update using (bucket_id = 'attachments' and public.is_member());

create policy "members delete attachments bucket" on storage.objects
  for delete using (bucket_id = 'attachments' and public.is_member());

-- ---------------------------------------------------------------------------
-- activity_log: lightweight audit trail (who did what, when)
-- ---------------------------------------------------------------------------
create table public.activity_log (
  id           uuid primary key default gen_random_uuid(),
  entity_type  text not null check (entity_type in ('section', 'task', 'chore')),
  entity_id    uuid not null,
  action       text not null check (action in ('created', 'updated', 'completed', 'uncompleted', 'deleted', 'restored', 'moved', 'renamed')),
  actor_id     uuid references public.members(id) on delete set null,
  summary      text,
  created_at   timestamptz not null default now()
);

create index activity_log_entity_idx on public.activity_log (entity_type, entity_id, created_at desc);
create index activity_log_created_idx on public.activity_log (created_at desc);

alter table public.activity_log enable row level security;

create policy "members full access to activity_log" on public.activity_log
  for all using (public.is_member()) with check (public.is_member());

-- ---------------------------------------------------------------------------
-- Realtime: publish row-level changes for every collaborative table
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table public.sections;
alter publication supabase_realtime add table public.tasks;
alter publication supabase_realtime add table public.chores;
alter publication supabase_realtime add table public.chore_completions;
alter publication supabase_realtime add table public.attachments;
alter publication supabase_realtime add table public.activity_log;

-- Yachad (the iOS companion app) — core schema
--
-- This is a SEPARATE Supabase project from the one the Next.js "K&H" website
-- uses. Nothing here touches, extends, or depends on that project or its
-- `supabase/migrations/` — see ios/README.md for why.
--
-- Unlike the website (one implicit shared household), this backend is
-- multi-tenant: anyone can create an "area" (a shared notes/tasks space),
-- invite others to it via a link or QR code, and approve each joiner with a
-- read-only or read-write permission. There is still no login/signup —
-- membership is scoped to a per-device id, and a person only ever identifies
-- themselves with a nickname (see 0002_access_control.sql for how that's
-- enforced without Supabase Auth).

create extension if not exists pgcrypto;

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
-- areas: the shared space ("household", "friend group", ...). Analogous to
-- the website's single implicit workspace, except here there can be any
-- number of them, each with its own membership.
-- ---------------------------------------------------------------------------
create table public.areas (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  emoji         text,
  invite_code   text not null unique default encode(gen_random_bytes(6), 'base64'),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create trigger areas_set_updated_at
  before update on public.areas
  for each row execute function public.set_updated_at();

-- invite_code is url/QR-safe (base64 can contain '/', '+' — normalize it).
create or replace function public.normalize_invite_code()
returns trigger
language plpgsql
as $$
begin
  new.invite_code := translate(new.invite_code, '/+=', '_-');
  return new;
end;
$$;

create trigger areas_normalize_invite_code
  before insert or update of invite_code on public.areas
  for each row execute function public.normalize_invite_code();

-- ---------------------------------------------------------------------------
-- area_members: one row per (area, device). No auth — a "device" is a random
-- uuid the app generates once and stores locally (see DeviceIdentity.swift).
-- Membership starts 'pending' for everyone except the creator (auto-'approved'
-- as 'owner'); the owner then picks 'viewer' (read-only) or 'editor'
-- (read-write) when approving.
-- ---------------------------------------------------------------------------
create table public.area_members (
  id            uuid primary key default gen_random_uuid(),
  area_id       uuid not null references public.areas(id) on delete cascade,
  device_id     uuid not null,
  nickname      text not null check (char_length(btrim(nickname)) between 1 and 40),
  role          text not null default 'viewer' check (role in ('owner', 'editor', 'viewer')),
  status        text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  color         text not null default '#6366f1',
  avatar_emoji  text,
  requested_at  timestamptz not null default now(),
  approved_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  unique (area_id, device_id)
);

create index area_members_area_idx on public.area_members (area_id, status);
create index area_members_device_idx on public.area_members (device_id);

create trigger area_members_set_updated_at
  before update on public.area_members
  for each row execute function public.set_updated_at();

-- Only one 'owner' per area — ownership is fixed at creation time (transfer
-- is a deliberately unsupported v1 simplification, same spirit as the
-- website's deferred-features list).
create unique index area_members_one_owner_idx on public.area_members (area_id) where role = 'owner';

-- ---------------------------------------------------------------------------
-- sections — identical shape/purpose to the website's `sections`.
-- ---------------------------------------------------------------------------
create table public.sections (
  id           uuid primary key default gen_random_uuid(),
  area_id      uuid not null references public.areas(id) on delete cascade,
  name         text not null,
  emoji        text,
  kind         text not null default 'tasks' check (kind in ('tasks', 'shopping', 'chores', 'info')),
  color        text,
  description  text,
  position     text not null,
  deleted_at   timestamptz,
  created_by   uuid references public.area_members(id) on delete set null,
  updated_by   uuid references public.area_members(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index sections_area_position_idx on public.sections (area_id, position) where deleted_at is null;

create trigger sections_set_updated_at
  before update on public.sections
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- tasks — unified tasks + unlimited-depth subtasks + shopping-flavored
-- fields, same design as the website's `tasks` table.
-- ---------------------------------------------------------------------------
create table public.tasks (
  id              uuid primary key default gen_random_uuid(),
  area_id         uuid not null references public.areas(id) on delete cascade,
  section_id      uuid not null references public.sections(id) on delete cascade,
  parent_task_id  uuid references public.tasks(id) on delete cascade,
  position        text not null,

  title           text not null default '',
  notes           text,
  emoji           text,
  priority        smallint check (priority between 0 and 3),
  due_at          timestamptz,
  due_end_at      timestamptz,
  tags            text[] not null default '{}',
  is_note         boolean not null default false,

  assignee_member_id uuid references public.area_members(id) on delete set null,

  is_completed    boolean not null default false,
  completed_at    timestamptz,
  completed_by    uuid references public.area_members(id) on delete set null,

  -- shopping-flavored fields (nullable, ignored outside shopping-kind sections)
  quantity        numeric,
  unit            text,
  price           numeric(10, 2),
  currency        text default 'ILS',
  brand           text,

  deleted_at      timestamptz,
  created_by      uuid references public.area_members(id) on delete set null,
  updated_by      uuid references public.area_members(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint completed_shape check (is_completed = (completed_at is not null))
);

create index tasks_area_section_parent_position_idx
  on public.tasks (area_id, section_id, parent_task_id, position) where deleted_at is null;
create index tasks_parent_idx on public.tasks (parent_task_id) where deleted_at is null;
create index tasks_due_idx on public.tasks (due_at) where deleted_at is null and is_completed = false;
create index tasks_tags_idx on public.tasks using gin (tags);

create trigger tasks_set_updated_at
  before update on public.tasks
  for each row execute function public.set_updated_at();

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
-- chores: recurring rule + append-only completion history (same design as
-- the website's `chores` + `chore_completions`).
-- ---------------------------------------------------------------------------
create table public.chores (
  id                 uuid primary key default gen_random_uuid(),
  area_id            uuid not null references public.areas(id) on delete cascade,
  section_id         uuid not null references public.sections(id) on delete cascade,
  title              text not null,
  notes              text,
  emoji              text,
  position           text not null,

  assignee_member_id uuid references public.area_members(id) on delete set null,

  freq               text not null check (freq in ('daily', 'weekly', 'monthly', 'custom', 'as_needed')),
  interval_n         int not null default 1,
  weekdays           int[],
  month_day          int,
  anchor_date        date not null default current_date,
  next_due_at        timestamptz not null default now(),

  deleted_at         timestamptz,
  created_by         uuid references public.area_members(id) on delete set null,
  updated_by         uuid references public.area_members(id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index chores_area_next_due_idx on public.chores (area_id, next_due_at) where deleted_at is null;

create trigger chores_set_updated_at
  before update on public.chores
  for each row execute function public.set_updated_at();

create table public.chore_completions (
  id            uuid primary key default gen_random_uuid(),
  area_id       uuid not null references public.areas(id) on delete cascade,
  chore_id      uuid not null references public.chores(id) on delete cascade,
  completed_by  uuid not null references public.area_members(id) on delete cascade,
  completed_at  timestamptz not null default now(),
  due_at        timestamptz not null,
  created_at    timestamptz not null default now()
);

create index chore_completions_chore_idx on public.chore_completions (chore_id, completed_at desc);

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

  insert into public.chore_completions (area_id, chore_id, completed_by, due_at)
  values (c.area_id, p_chore_id, p_completed_by, c.next_due_at);

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
-- calendar_events — trips/birthdays/reminders on a month grid (the
-- website's `family_events`, generalized per-area).
-- ---------------------------------------------------------------------------
create table public.calendar_events (
  id            uuid primary key default gen_random_uuid(),
  area_id       uuid not null references public.areas(id) on delete cascade,
  title         text not null,
  emoji         text,
  notes         text,
  kind          text not null default 'other' check (kind in ('birthday', 'medical', 'other')),
  event_date    date not null,
  end_date      date,
  recurrence    text not null default 'none' check (recurrence in ('none', 'yearly')),
  deleted_at    timestamptz,
  created_by    uuid references public.area_members(id) on delete set null,
  updated_by    uuid references public.area_members(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index calendar_events_area_date_idx on public.calendar_events (area_id, event_date) where deleted_at is null;

create trigger calendar_events_set_updated_at
  before update on public.calendar_events
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- activity_log: lightweight "who did what, when" audit trail, per area.
-- ---------------------------------------------------------------------------
create table public.activity_log (
  id           uuid primary key default gen_random_uuid(),
  area_id      uuid not null references public.areas(id) on delete cascade,
  entity_type  text not null check (entity_type in ('area', 'section', 'task', 'chore', 'calendar_event')),
  entity_id    uuid not null,
  action       text not null check (action in ('created', 'updated', 'completed', 'uncompleted', 'deleted', 'restored', 'joined', 'approved')),
  actor_id     uuid references public.area_members(id) on delete set null,
  summary      text,
  created_at   timestamptz not null default now()
);

create index activity_log_area_created_idx on public.activity_log (area_id, created_at desc);
create index activity_log_entity_idx on public.activity_log (entity_type, entity_id, created_at desc);

-- Access control without login.
--
-- Same philosophy as the website (see its README's "Access model" section):
-- there is no Supabase Auth, no email/password, nothing to sign up for. The
-- app generates a random device id once on first launch and stores it
-- locally (UserDefaults — deliberately not Keychain, since it is an
-- attribution key, not a secret, exactly like the website's localStorage
-- identity picker). Every request carries that id in an `x-device-id`
-- header, which Supabase/PostgREST exposes to RLS policies via the
-- `request.headers` GUC. A row in `area_members` (device_id, area_id,
-- status, role) is what turns "knows the invite link/QR" into "can read" or
-- "can read and write" for that one area — nothing more.
--
-- This is intentionally the same trust model the website documents for
-- itself: possessing the invite is most of the access control; RLS mainly
-- exists to keep areas from leaking into each other and to enforce
-- read-only vs read-write once someone is approved.

create or replace function public.request_device_id()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.headers', true)::json ->> 'x-device-id', '')::uuid;
$$;

create or replace function public.can_read_area(p_area_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.area_members m
    where m.area_id = p_area_id
      and m.device_id = public.request_device_id()
      and m.status = 'approved'
  );
$$;

create or replace function public.can_write_area(p_area_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.area_members m
    where m.area_id = p_area_id
      and m.device_id = public.request_device_id()
      and m.status = 'approved'
      and m.role in ('owner', 'editor')
  );
$$;

create or replace function public.is_area_owner(p_area_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.area_members m
    where m.area_id = p_area_id
      and m.device_id = public.request_device_id()
      and m.status = 'approved'
      and m.role = 'owner'
  );
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.areas enable row level security;
alter table public.area_members enable row level security;
alter table public.sections enable row level security;
alter table public.tasks enable row level security;
alter table public.chores enable row level security;
alter table public.chore_completions enable row level security;
alter table public.calendar_events enable row level security;
alter table public.activity_log enable row level security;

-- areas: readable once you're an approved member. No direct insert/update/
-- delete from the client — that only happens through the RPCs below, which
-- run as security definer, so ownership can never be forged.
create policy "areas readable by members" on public.areas
  for select using (public.can_read_area(id));

-- area_members: an approved member can see the whole roster; a pending/
-- rejected joiner can see (only) their own row, so the app can show them
-- "waiting for approval". No direct insert (see request_join_area /
-- create_area RPCs). Only the owner can update roles/status; anyone can
-- delete (leave) their own membership row.
create policy "area_members readable by members or self" on public.area_members
  for select using (
    public.can_read_area(area_id) or device_id = public.request_device_id()
  );

create policy "area_members updatable by owner" on public.area_members
  for update using (public.is_area_owner(area_id))
  with check (public.is_area_owner(area_id));

create policy "area_members self nickname update" on public.area_members
  for update using (device_id = public.request_device_id())
  with check (device_id = public.request_device_id());

create policy "area_members deletable by owner or self" on public.area_members
  for delete using (public.is_area_owner(area_id) or device_id = public.request_device_id());

-- Content tables: read for any approved member, write for owner/editor.
create policy "sections readable" on public.sections
  for select using (public.can_read_area(area_id));
create policy "sections writable" on public.sections
  for insert with check (public.can_write_area(area_id));
create policy "sections updatable" on public.sections
  for update using (public.can_write_area(area_id)) with check (public.can_write_area(area_id));
create policy "sections deletable" on public.sections
  for delete using (public.can_write_area(area_id));

create policy "tasks readable" on public.tasks
  for select using (public.can_read_area(area_id));
create policy "tasks writable" on public.tasks
  for insert with check (public.can_write_area(area_id));
create policy "tasks updatable" on public.tasks
  for update using (public.can_write_area(area_id)) with check (public.can_write_area(area_id));
create policy "tasks deletable" on public.tasks
  for delete using (public.can_write_area(area_id));

create policy "chores readable" on public.chores
  for select using (public.can_read_area(area_id));
create policy "chores writable" on public.chores
  for insert with check (public.can_write_area(area_id));
create policy "chores updatable" on public.chores
  for update using (public.can_write_area(area_id)) with check (public.can_write_area(area_id));
create policy "chores deletable" on public.chores
  for delete using (public.can_write_area(area_id));

create policy "chore_completions readable" on public.chore_completions
  for select using (public.can_read_area(area_id));
create policy "chore_completions writable" on public.chore_completions
  for insert with check (public.can_write_area(area_id));

create policy "calendar_events readable" on public.calendar_events
  for select using (public.can_read_area(area_id));
create policy "calendar_events writable" on public.calendar_events
  for insert with check (public.can_write_area(area_id));
create policy "calendar_events updatable" on public.calendar_events
  for update using (public.can_write_area(area_id)) with check (public.can_write_area(area_id));
create policy "calendar_events deletable" on public.calendar_events
  for delete using (public.can_write_area(area_id));

create policy "activity_log readable" on public.activity_log
  for select using (public.can_read_area(area_id));

-- The two UPDATE policies above are OR'd together (both permissive), so a
-- pending member could otherwise ride the "update my own row" policy to
-- approve themselves. Lock role/status/approved_at down to owner-only at the
-- trigger level, regardless of which policy let the UPDATE through.
create or replace function public.guard_area_member_privileged_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_area_owner(new.area_id) then
    new.role := old.role;
    new.status := old.status;
    new.approved_at := old.approved_at;
  end if;
  return new;
end;
$$;

create trigger area_members_guard_privileged_columns
  before update on public.area_members
  for each row execute function public.guard_area_member_privileged_columns();

-- ---------------------------------------------------------------------------
-- RPCs: the only way to create an area or join one. Both are
-- security definer so they can insert into area_members (which has no
-- client-facing insert policy) while still being safe: create_area always
-- makes the caller's own device the owner, and request_join_area always
-- inserts a 'pending' row for the caller's own device — neither can be used
-- to act on someone else's behalf.
-- ---------------------------------------------------------------------------
create or replace function public.create_area(p_name text, p_emoji text, p_nickname text)
returns public.areas
language plpgsql
security definer
set search_path = public
as $$
declare
  v_device uuid := public.request_device_id();
  v_area public.areas;
begin
  if v_device is null then
    raise exception 'missing x-device-id header';
  end if;

  insert into public.areas (name, emoji) values (p_name, p_emoji)
  returning * into v_area;

  insert into public.area_members (area_id, device_id, nickname, role, status, approved_at)
  values (v_area.id, v_device, p_nickname, 'owner', 'approved', now());

  insert into public.activity_log (area_id, entity_type, entity_id, action, actor_id, summary)
  select v_area.id, 'area', v_area.id, 'created', m.id, p_name
  from public.area_members m where m.area_id = v_area.id and m.device_id = v_device;

  return v_area;
end;
$$;

-- Looks up an area by its (normalized) invite code — used to preview "you're
-- about to join <name>" before the joiner has any area_members row yet, so
-- it can't go through the normal can_read_area()-gated select policy.
create or replace function public.area_preview_by_invite_code(p_invite_code text)
returns table (id uuid, name text, emoji text)
language sql
stable
security definer
set search_path = public
as $$
  select a.id, a.name, a.emoji
  from public.areas a
  where a.invite_code = translate(p_invite_code, '/+=', '_-');
$$;

create or replace function public.request_join_area(p_invite_code text, p_nickname text)
returns public.area_members
language plpgsql
security definer
set search_path = public
as $$
declare
  v_device uuid := public.request_device_id();
  v_area_id uuid;
  v_member public.area_members;
begin
  if v_device is null then
    raise exception 'missing x-device-id header';
  end if;

  select id into v_area_id from public.areas where invite_code = translate(p_invite_code, '/+=', '_-');
  if v_area_id is null then
    raise exception 'invalid invite code';
  end if;

  insert into public.area_members (area_id, device_id, nickname, role, status)
  values (v_area_id, v_device, p_nickname, 'viewer', 'pending')
  on conflict (area_id, device_id)
    do update set nickname = excluded.nickname
  returning * into v_member;

  return v_member;
end;
$$;

create or replace function public.approve_area_member(p_member_id uuid, p_role text)
returns public.area_members
language plpgsql
security definer
set search_path = public
as $$
declare
  v_area_id uuid;
  v_member public.area_members;
begin
  if p_role not in ('editor', 'viewer') then
    raise exception 'role must be editor or viewer';
  end if;

  select area_id into v_area_id from public.area_members where id = p_member_id;
  if not public.is_area_owner(v_area_id) then
    raise exception 'only the owner can approve members';
  end if;

  update public.area_members
  set status = 'approved', role = p_role, approved_at = now()
  where id = p_member_id
  returning * into v_member;

  insert into public.activity_log (area_id, entity_type, entity_id, action, actor_id, summary)
  values (v_area_id, 'area', v_area_id, 'approved', p_member_id, v_member.nickname);

  return v_member;
end;
$$;

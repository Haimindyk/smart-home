-- Push notifications.
--
-- The device (not a person, not an area) is what registers for push — one
-- device can hold approved membership in several areas, and one push token
-- covers all of them. Delivery itself happens outside Postgres: this file
-- only stores tokens and fires an async HTTP call (via the `pg_net`
-- extension) to a Supabase Edge Function whenever something worth
-- notifying about happens; the Edge Function is what actually talks to
-- APNs. See ios/backend/functions/send-push/ for that function, and
-- ios/README.md for the manual setup this needs (an APNs auth key, and two
-- secrets in Supabase Vault) — none of which can be provisioned from this
-- repo alone.

create table public.push_tokens (
  device_id     uuid primary key,
  apns_token    text not null,
  environment   text not null default 'sandbox' check (environment in ('sandbox', 'production')),
  updated_at    timestamptz not null default now()
);

alter table public.push_tokens enable row level security;

create policy "push_tokens manage own" on public.push_tokens
  for all using (device_id = public.request_device_id())
  with check (device_id = public.request_device_id());

create or replace function public.push_tokens_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger push_tokens_set_updated_at
  before update on public.push_tokens
  for each row execute function public.push_tokens_set_updated_at();

-- ---------------------------------------------------------------------------
-- Sending: fire-and-forget HTTP call to the Edge Function per device. Reads
-- the function's URL and a shared secret from Supabase Vault (set these up
-- once after deploying the function — see ios/README.md — rather than
-- hardcoding a project ref or key into a migration file).
-- ---------------------------------------------------------------------------
create extension if not exists pg_net with schema extensions;

create or replace function public.notify_devices(p_device_ids uuid[], p_title text, p_body text, p_data jsonb default '{}'::jsonb)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_url text;
  v_secret text;
begin
  if p_device_ids is null or array_length(p_device_ids, 1) is null then
    return;
  end if;

  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'push_edge_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'push_edge_secret';
  if v_url is null or v_secret is null then
    -- Push isn't configured yet (Vault secrets not set) — no-op rather
    -- than error, so the rest of the app keeps working without push.
    return;
  end if;

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_secret),
    body := jsonb_build_object('deviceIds', to_jsonb(p_device_ids), 'title', p_title, 'body', p_body, 'data', p_data)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Triggers: the three events worth an immediate push.
-- ---------------------------------------------------------------------------

-- New pending join request -> every owner/manager device in the area.
create or replace function public.notify_on_join_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_area_name text;
  v_manager_devices uuid[];
begin
  if new.status <> 'pending' then
    return new;
  end if;

  select name into v_area_name from public.areas where id = new.area_id;
  select array_agg(device_id) into v_manager_devices
  from public.area_members
  where area_id = new.area_id and status = 'approved' and role in ('owner', 'manager');

  perform public.notify_devices(
    v_manager_devices,
    v_area_name,
    new.nickname || ' מבקש/ת להצטרף',
    jsonb_build_object('kind', 'join_request', 'area_id', new.area_id)
  );
  return new;
end;
$$;

create trigger area_members_notify_join_request
  after insert on public.area_members
  for each row execute function public.notify_on_join_request();

-- Approved -> the joiner's own device.
create or replace function public.notify_on_approval()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_area_name text;
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    select name into v_area_name from public.areas where id = new.area_id;
    perform public.notify_devices(
      array[new.device_id],
      v_area_name,
      'אושרת להצטרף! 🎉',
      jsonb_build_object('kind', 'approved', 'area_id', new.area_id)
    );
  end if;
  return new;
end;
$$;

create trigger area_members_notify_approval
  after update on public.area_members
  for each row execute function public.notify_on_approval();

-- Newly assigned to a task -> each newly-added assignee's device.
create or replace function public.notify_on_task_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_assignee_ids uuid[];
  v_new_devices uuid[];
  v_area_name text;
begin
  if tg_op = 'INSERT' then
    v_new_assignee_ids := new.assignee_member_ids;
  else
    select array_agg(x) into v_new_assignee_ids
    from unnest(new.assignee_member_ids) x
    where x <> all (coalesce(old.assignee_member_ids, '{}'));
  end if;

  if v_new_assignee_ids is null or array_length(v_new_assignee_ids, 1) is null then
    return new;
  end if;

  select array_agg(device_id) into v_new_devices
  from public.area_members
  where id = any(v_new_assignee_ids);

  select name into v_area_name from public.areas where id = new.area_id;
  perform public.notify_devices(
    v_new_devices,
    v_area_name,
    'שויכת ל: ' || new.title,
    jsonb_build_object('kind', 'assigned', 'area_id', new.area_id, 'task_id', new.id)
  );
  return new;
end;
$$;

create trigger tasks_notify_assignment
  after insert or update of assignee_member_ids on public.tasks
  for each row execute function public.notify_on_task_assignment();

-- ---------------------------------------------------------------------------
-- Scheduled: a once-daily "due today" sweep for tasks and chores, mirroring
-- the website's own due-date reminders. Requires the `pg_cron` extension
-- (enable it from the Supabase dashboard's Database > Extensions if the
-- CREATE EXTENSION below is rejected — some plans require enabling it there
-- instead of via SQL).
-- ---------------------------------------------------------------------------
create extension if not exists pg_cron;

create or replace function public.send_due_today_reminders()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  for r in
    select t.id, t.title, t.area_id, a.name as area_name, unnest(t.assignee_member_ids) as assignee_id
    from public.tasks t
    join public.areas a on a.id = t.area_id
    where t.deleted_at is null and t.is_completed = false
      and t.due_at is not null and t.due_at::date = current_date
  loop
    perform public.notify_devices(
      (select array_agg(device_id) from public.area_members where id = r.assignee_id),
      r.area_name,
      'היום: ' || r.title,
      jsonb_build_object('kind', 'due_today', 'area_id', r.area_id, 'task_id', r.id)
    );
  end loop;

  for r in
    select c.id, c.title, c.area_id, a.name as area_name, unnest(c.assignee_member_ids) as assignee_id
    from public.chores c
    join public.areas a on a.id = c.area_id
    where c.deleted_at is null and c.next_due_at::date = current_date
  loop
    perform public.notify_devices(
      (select array_agg(device_id) from public.area_members where id = r.assignee_id),
      r.area_name,
      'מטלה להיום: ' || r.title,
      jsonb_build_object('kind', 'chore_due_today', 'area_id', r.area_id, 'chore_id', r.id)
    );
  end loop;
end;
$$;

select cron.schedule('yachad-due-today-reminders', '0 7 * * *', $$select public.send_due_today_reminders()$$);

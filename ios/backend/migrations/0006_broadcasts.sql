-- Broadcast messages: a one-way announcement from the owner/a manager to
-- every approved member of an area ("everyone please bring milk", "we're
-- meeting at 6 instead of 7"). Not a chat — just a short message with a
-- timestamp and who sent it, delivered as a dashboard banner (until
-- dismissed) plus a push notification.

create table public.broadcasts (
  id          uuid primary key default gen_random_uuid(),
  area_id     uuid not null references public.areas(id) on delete cascade,
  message     text not null check (char_length(btrim(message)) between 1 and 500),
  sent_by     uuid references public.area_members(id) on delete set null,
  created_at  timestamptz not null default now()
);

create index broadcasts_area_created_idx on public.broadcasts (area_id, created_at desc);

alter table public.broadcasts enable row level security;

create policy "broadcasts readable" on public.broadcasts
  for select using (public.can_read_area(area_id));

create policy "broadcasts sendable by manager" on public.broadcasts
  for insert with check (public.can_manage_area(area_id));

alter publication supabase_realtime add table public.broadcasts;

-- Push every approved member (the sender included — harmless, and keeps
-- this simple) the moment a broadcast goes out.
create or replace function public.notify_on_broadcast()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_area_name text;
  v_sender_nickname text;
  v_devices uuid[];
begin
  select name into v_area_name from public.areas where id = new.area_id;
  select nickname into v_sender_nickname from public.area_members where id = new.sent_by;
  select array_agg(device_id) into v_devices
  from public.area_members
  where area_id = new.area_id and status = 'approved';

  perform public.notify_devices(
    v_devices,
    coalesce(v_sender_nickname, v_area_name) || ' · ' || v_area_name,
    new.message,
    jsonb_build_object('kind', 'broadcast', 'area_id', new.area_id, 'broadcast_id', new.id)
  );
  return new;
end;
$$;

create trigger broadcasts_notify
  after insert on public.broadcasts
  for each row execute function public.notify_on_broadcast();

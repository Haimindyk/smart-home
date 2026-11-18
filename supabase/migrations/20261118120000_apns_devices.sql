-- Native iOS push: one row per app installation (APNs device token), tagged with the member who
-- registered it. The `send-push` Edge Function fans each activity_log insert out to these devices
-- through APNs, with the same per-member preferences (notification_prefs) as Web Push.
create table if not exists public.apns_devices (
  id          uuid primary key default gen_random_uuid(),
  member_id   uuid references public.members(id) on delete cascade,
  token       text not null unique check (token ~ '^[0-9a-fA-F]{32,200}$'),
  -- TestFlight and App Store builds use the production APNs host; Xcode debug builds use the sandbox.
  environment text not null default 'production' check (environment in ('production', 'sandbox')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.apns_devices enable row level security;

create policy "members full access to apns_devices" on public.apns_devices
  for all using (public.is_member()) with check (public.is_member());

grant select, insert, update, delete on public.apns_devices to authenticated;

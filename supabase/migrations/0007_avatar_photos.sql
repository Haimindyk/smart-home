-- Self-serve profile photos: members can upload a real picture instead of
-- (or in addition to) picking an emoji. avatar_photo_url takes priority
-- over avatar_emoji everywhere an avatar is shown, including as the icon
-- on push notifications (see supabase/functions/send-push).
--
-- Unlike the private "attachments" bucket, avatars are public: the app has
-- no real auth/access-control model to begin with (see 0002_open_access.sql),
-- and a stable public URL is what a push notification's `icon` field needs
-- (a signed URL would expire before the OS gets around to rendering it).

alter table public.members add column if not exists avatar_photo_url text;

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

create policy "members write avatars bucket" on storage.objects
  for insert with check (bucket_id = 'avatars' and public.is_member());

create policy "members update avatars bucket" on storage.objects
  for update using (bucket_id = 'avatars' and public.is_member());

create policy "members delete avatars bucket" on storage.objects
  for delete using (bucket_id = 'avatars' and public.is_member());

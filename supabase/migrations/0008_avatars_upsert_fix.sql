-- Real bug found live: uploading a profile photo failed on every device
-- (confirmed via storage logs: a genuine 400 from an iPhone). Root cause —
-- 0007 gave the avatars bucket insert/update/delete policies but no select
-- policy, assuming a public bucket's reads bypass RLS entirely. They do for
-- the public CDN read path, but supabase-js's upload(..., {upsert: true})
-- (what the client actually calls) sends an `x-upsert: true` header, and the
-- storage API's upsert path does an internal existence check that goes
-- through the authenticated select path, not the public one — so it was
-- blocked by RLS with no matching policy. A plain insert (no upsert) worked
-- fine, which is why this wasn't caught by the earlier direct-upload test
-- (it didn't call upsert:true) but broke for real users the moment they
-- re-uploaded a photo, or on any browser whose client library defaults to
-- upsert semantics.

create policy "members read avatars bucket" on storage.objects
  for select using (bucket_id = 'avatars' and public.is_member());

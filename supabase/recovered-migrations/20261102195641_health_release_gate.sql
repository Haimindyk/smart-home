-- Do not expose personal tracking while the old plaintext/local PIN client
-- is still in production. The identity migration opens this gate atomically.
create table public.health_release_state(id boolean primary key default true check(id),personal_access_ready boolean not null default false);
insert into public.health_release_state(id,personal_access_ready) values(true,to_regclass('private.member_credentials') is not null);
alter table public.health_release_state enable row level security;
revoke all on public.health_release_state from public,anon,authenticated;
grant select on public.health_release_state to authenticated;
grant all on public.health_release_state to service_role;
create policy health_release_read on public.health_release_state for select to authenticated using(true);
do $$ declare t text; condition text='owner_user_id=(select auth.uid()) and exists(select 1 from public.members m where m.user_id=(select auth.uid())) and exists(select 1 from public.health_release_state where personal_access_ready)'; begin
 foreach t in array array['health_profiles','nutrition_goals','personal_foods','recipes','meals','water_logs','weight_logs','workout_plans','workout_sessions'] loop
 execute format('alter policy owner_access on public.%I using (%s) with check (%s)',t,condition,condition);
 end loop;
end $$;
alter policy analysis_owner_read on public.nutrition_analyses using(owner_user_id=(select auth.uid()) and exists(select 1 from public.health_release_state where personal_access_ready));
alter policy analysis_owner_delete on public.nutrition_analyses using(owner_user_id=(select auth.uid()) and exists(select 1 from public.health_release_state where personal_access_ready));
alter policy health_image_read on storage.objects using(bucket_id='health-images' and (storage.foldername(name))[1]=(select auth.uid())::text and exists(select 1 from public.members m where m.user_id=(select auth.uid())) and exists(select 1 from public.health_release_state where personal_access_ready));
alter policy health_image_insert on storage.objects with check(bucket_id='health-images' and (storage.foldername(name))[1]=(select auth.uid())::text and exists(select 1 from public.members m where m.user_id=(select auth.uid())) and exists(select 1 from public.health_release_state where personal_access_ready));
alter policy health_image_delete on storage.objects using(bucket_id='health-images' and (storage.foldername(name))[1]=(select auth.uid())::text and exists(select 1 from public.members m where m.user_id=(select auth.uid())) and exists(select 1 from public.health_release_state where personal_access_ready));

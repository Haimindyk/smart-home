-- Personal health is isolated from the deliberately shared household workspace.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function public.health_valid_food(f jsonb) returns boolean language sql immutable set search_path = '' as $$
 select coalesce(jsonb_typeof(f)='object' and length(f->>'name') between 1 and 200
 and f->>'source' in ('manual','label','ai','usda','openfoodfacts','recipe')
 and f->>'basis' in ('g','ml') and jsonb_typeof(f->'per100')='object'
 and not exists (select 1 from unnest(array['kcal','protein','carbs','fat']) k
 where jsonb_typeof(f->'per100'->k) is distinct from 'number'
 or not coalesce((f->'per100'->>k)::numeric between 0 and 10000,false)), false);
$$;
create or replace function public.health_valid_items(items jsonb) returns boolean language sql immutable set search_path = '' as $$
 select case when jsonb_typeof(items) <> 'array' then false else
 jsonb_array_length(items) between 1 and 100 and not exists (
 select 1 from jsonb_array_elements(items) i where not public.health_valid_food(i->'food')
 or jsonb_typeof(i->'quantity') is distinct from 'number'
 or not coalesce((i->>'quantity')::numeric > 0 and (i->>'quantity')::numeric <= 10000,false)) end;
$$;
create or replace function public.health_number(d jsonb,k text,lo numeric,hi numeric) returns boolean language sql immutable set search_path='' as $$
 select case when jsonb_typeof(d->k)='number' then (d->>k)::numeric between lo and hi else false end;
$$;
create or replace function public.health_valid_exercises(items jsonb,performed boolean) returns boolean language plpgsql immutable set search_path='' as $$
declare e jsonb; s jsonb;
begin
 if jsonb_typeof(items) is distinct from 'array' or jsonb_array_length(items)>100 then return false; end if;
 for e in select value from jsonb_array_elements(items) loop
 if not coalesce(length(e->>'name') between 1 and 150 and e->>'kind' in ('strength','cardio') and public.health_number(e,'sets',1,30) and public.health_number(e,'reps',1,500) and public.health_number(e,'weight',0,1000) and public.health_number(e,'rest',0,1800) and public.health_number(e,'duration',0,1440) and public.health_number(e,'distance',0,1000),false) then return false; end if;
 if performed then
 if jsonb_typeof(e->'skipped') is distinct from 'boolean' or jsonb_typeof(e->'performed') is distinct from 'array' or jsonb_array_length(e->'performed')>50 then return false;end if;
 for s in select value from jsonb_array_elements(e->'performed') loop
 if jsonb_typeof(s->'done') is distinct from 'boolean' or not public.health_number(s,'reps',0,500) or not public.health_number(s,'weight',0,1000) or not public.health_number(s,'duration',0,1440) or not public.health_number(s,'distance',0,1000) then return false; end if;
 end loop;
 end if;
 end loop;
 return true;
exception when others then return false;
end;
$$;
create or replace function public.health_valid_data(kind text, d jsonb) returns boolean language plpgsql immutable set search_path = '' as $$
begin
 if jsonb_typeof(d) <> 'object' or octet_length(d::text)>200000 then return false; end if;
 if kind in ('meals','water_logs','weight_logs','nutrition_goals','workout_sessions') then
  if d->>'date' is null or (d->>'date') !~ '^\d{4}-\d{2}-\d{2}$' or (d->>'date')::date::text <> d->>'date' then return false; end if;
 end if;
 return coalesce(case kind
 when 'health_profiles' then jsonb_typeof(d->'nutritionEnabled')='boolean' and jsonb_typeof(d->'workoutsEnabled')='boolean' and jsonb_typeof(d->'aiConsent')='boolean' and public.health_number(d,'waterTarget',250,10000) and exists(select 1 from pg_catalog.pg_timezone_names where name=d->>'timezone')
 when 'nutrition_goals' then (d->>'kcal')::numeric between 500 and 10000 and (d->>'protein')::numeric between 0 and 500 and (d->>'fat')::numeric between 0 and 500 and (d->>'carbs')::numeric between 0 and 1500 and d->>'method' in ('manual','calculated')
 when 'personal_foods' then public.health_valid_food(d)
 when 'recipes' then length(d->>'name') between 1 and 200 and (d->>'servings')::numeric > 0 and public.health_valid_items(d->'items') and not exists(select 1 from jsonb_array_elements(d->'items') i where i->'food'->>'basis'<>'g')
 when 'meals' then d->>'kind' in ('breakfast','lunch','dinner','snack') and public.health_valid_items(d->'items')
 when 'water_logs' then (d->>'amount')::numeric between 1 and 5000
 when 'weight_logs' then (d->>'weight')::numeric between 20 and 400
 when 'workout_plans' then length(d->>'name') between 1 and 150 and jsonb_typeof(d->'archived')='boolean' and public.health_valid_exercises(d->'exercises',false) and jsonb_array_length(d->'exercises') between 1 and 100 and jsonb_typeof(d->'days')='array' and not exists(select 1 from jsonb_array_elements_text(d->'days') x where x::int not between 0 and 6)
 when 'workout_sessions' then length(d->>'name') between 1 and 150 and d->>'status' in ('active','partial','completed','cancelled') and jsonb_typeof(d->'quick')='boolean' and public.health_valid_exercises(d->'exercises',true)
 else false end,false);
exception when others then return false;
end;
$$;

create or replace function public.health_version_guard() returns trigger language plpgsql set search_path = '' as $$
begin
 if new.owner_user_id is distinct from old.owner_user_id or new.id is distinct from old.id then raise exception 'immutable_owner'; end if;
 if new.version <> old.version+1 then raise exception 'version_conflict' using errcode='40001'; end if;
 new.created_at=old.created_at; new.updated_at=now(); return new;
end;
$$;
create or replace function public.health_image_owner_guard() returns trigger language plpgsql set search_path = '' as $$
begin
 if new.data->>'imagePath' is not null and split_part(new.data->>'imagePath','/',1) <> new.owner_user_id::text then raise exception 'invalid_image_owner'; end if;
 return new;
end;
$$;

create table public.health_profiles (
 id uuid primary key default gen_random_uuid(), owner_user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 data jsonb not null check (public.health_valid_data('health_profiles',data)), version integer not null default 1 check(version>0), last_mutation_id uuid not null default gen_random_uuid(),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
 unique(id,owner_user_id)
);
alter table public.health_profiles enable row level security;
create policy owner_access on public.health_profiles for all to authenticated using(owner_user_id=(select auth.uid()) and exists(select 1 from public.members m where m.user_id=(select auth.uid()))) with check(owner_user_id=(select auth.uid()) and exists(select 1 from public.members m where m.user_id=(select auth.uid())));
revoke all on public.health_profiles from anon;
grant select,insert,update,delete on public.health_profiles to authenticated;
create index health_profiles_owner_updated on public.health_profiles(owner_user_id,updated_at);
create trigger health_version before update on public.health_profiles for each row execute function public.health_version_guard();

create table public.nutrition_goals (
 id uuid primary key default gen_random_uuid(), owner_user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 data jsonb not null check (public.health_valid_data('nutrition_goals',data)), version integer not null default 1 check(version>0), last_mutation_id uuid not null default gen_random_uuid(),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
 unique(id,owner_user_id)
);
alter table public.nutrition_goals enable row level security;
create policy owner_access on public.nutrition_goals for all to authenticated using(owner_user_id=(select auth.uid()) and exists(select 1 from public.members m where m.user_id=(select auth.uid()))) with check(owner_user_id=(select auth.uid()) and exists(select 1 from public.members m where m.user_id=(select auth.uid())));
revoke all on public.nutrition_goals from anon;
grant select,insert,update,delete on public.nutrition_goals to authenticated;
create index nutrition_goals_owner_updated on public.nutrition_goals(owner_user_id,updated_at);
create trigger health_version before update on public.nutrition_goals for each row execute function public.health_version_guard();
create index nutrition_goals_owner_date on public.nutrition_goals(owner_user_id,(data->>'date')) where deleted_at is null;

create table public.personal_foods (
 id uuid primary key default gen_random_uuid(), owner_user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 data jsonb not null check (public.health_valid_data('personal_foods',data)), version integer not null default 1 check(version>0), last_mutation_id uuid not null default gen_random_uuid(),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
 unique(id,owner_user_id)
);
alter table public.personal_foods enable row level security;
create policy owner_access on public.personal_foods for all to authenticated using(owner_user_id=(select auth.uid()) and exists(select 1 from public.members m where m.user_id=(select auth.uid()))) with check(owner_user_id=(select auth.uid()) and exists(select 1 from public.members m where m.user_id=(select auth.uid())));
revoke all on public.personal_foods from anon;
grant select,insert,update,delete on public.personal_foods to authenticated;
create index personal_foods_owner_updated on public.personal_foods(owner_user_id,updated_at);
create trigger health_version before update on public.personal_foods for each row execute function public.health_version_guard();

create table public.recipes (
 id uuid primary key default gen_random_uuid(), owner_user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 data jsonb not null check (public.health_valid_data('recipes',data)), version integer not null default 1 check(version>0), last_mutation_id uuid not null default gen_random_uuid(),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
 unique(id,owner_user_id)
);
alter table public.recipes enable row level security;
create policy owner_access on public.recipes for all to authenticated using(owner_user_id=(select auth.uid()) and exists(select 1 from public.members m where m.user_id=(select auth.uid()))) with check(owner_user_id=(select auth.uid()) and exists(select 1 from public.members m where m.user_id=(select auth.uid())));
revoke all on public.recipes from anon;
grant select,insert,update,delete on public.recipes to authenticated;
create index recipes_owner_updated on public.recipes(owner_user_id,updated_at);
create trigger health_version before update on public.recipes for each row execute function public.health_version_guard();

create table public.meals (
 id uuid primary key default gen_random_uuid(), owner_user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 data jsonb not null check (public.health_valid_data('meals',data)), version integer not null default 1 check(version>0), last_mutation_id uuid not null default gen_random_uuid(),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
 unique(id,owner_user_id)
);
alter table public.meals enable row level security;
create policy owner_access on public.meals for all to authenticated using(owner_user_id=(select auth.uid()) and exists(select 1 from public.members m where m.user_id=(select auth.uid()))) with check(owner_user_id=(select auth.uid()) and exists(select 1 from public.members m where m.user_id=(select auth.uid())));
revoke all on public.meals from anon;
grant select,insert,update,delete on public.meals to authenticated;
create index meals_owner_updated on public.meals(owner_user_id,updated_at);
create trigger health_version before update on public.meals for each row execute function public.health_version_guard();
create index meals_owner_date on public.meals(owner_user_id,(data->>'date')) where deleted_at is null;

create table public.water_logs (
 id uuid primary key default gen_random_uuid(), owner_user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 data jsonb not null check (public.health_valid_data('water_logs',data)), version integer not null default 1 check(version>0), last_mutation_id uuid not null default gen_random_uuid(),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
 unique(id,owner_user_id)
);
alter table public.water_logs enable row level security;
create policy owner_access on public.water_logs for all to authenticated using(owner_user_id=(select auth.uid()) and exists(select 1 from public.members m where m.user_id=(select auth.uid()))) with check(owner_user_id=(select auth.uid()) and exists(select 1 from public.members m where m.user_id=(select auth.uid())));
revoke all on public.water_logs from anon;
grant select,insert,update,delete on public.water_logs to authenticated;
create index water_logs_owner_updated on public.water_logs(owner_user_id,updated_at);
create trigger health_version before update on public.water_logs for each row execute function public.health_version_guard();
create index water_logs_owner_date on public.water_logs(owner_user_id,(data->>'date')) where deleted_at is null;

create table public.weight_logs (
 id uuid primary key default gen_random_uuid(), owner_user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 data jsonb not null check (public.health_valid_data('weight_logs',data)), version integer not null default 1 check(version>0), last_mutation_id uuid not null default gen_random_uuid(),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
 unique(id,owner_user_id)
);
alter table public.weight_logs enable row level security;
create policy owner_access on public.weight_logs for all to authenticated using(owner_user_id=(select auth.uid()) and exists(select 1 from public.members m where m.user_id=(select auth.uid()))) with check(owner_user_id=(select auth.uid()) and exists(select 1 from public.members m where m.user_id=(select auth.uid())));
revoke all on public.weight_logs from anon;
grant select,insert,update,delete on public.weight_logs to authenticated;
create index weight_logs_owner_updated on public.weight_logs(owner_user_id,updated_at);
create trigger health_version before update on public.weight_logs for each row execute function public.health_version_guard();
create index weight_logs_owner_date on public.weight_logs(owner_user_id,(data->>'date')) where deleted_at is null;

create table public.workout_plans (
 id uuid primary key default gen_random_uuid(), owner_user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 data jsonb not null check (public.health_valid_data('workout_plans',data)), version integer not null default 1 check(version>0), last_mutation_id uuid not null default gen_random_uuid(),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
 unique(id,owner_user_id)
);
alter table public.workout_plans enable row level security;
create policy owner_access on public.workout_plans for all to authenticated using(owner_user_id=(select auth.uid()) and exists(select 1 from public.members m where m.user_id=(select auth.uid()))) with check(owner_user_id=(select auth.uid()) and exists(select 1 from public.members m where m.user_id=(select auth.uid())));
revoke all on public.workout_plans from anon;
grant select,insert,update,delete on public.workout_plans to authenticated;
create index workout_plans_owner_updated on public.workout_plans(owner_user_id,updated_at);
create trigger health_version before update on public.workout_plans for each row execute function public.health_version_guard();

create table public.workout_sessions (
 id uuid primary key default gen_random_uuid(), owner_user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 data jsonb not null check (public.health_valid_data('workout_sessions',data)), version integer not null default 1 check(version>0), last_mutation_id uuid not null default gen_random_uuid(),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
 unique(id,owner_user_id)
);
alter table public.workout_sessions enable row level security;
create policy owner_access on public.workout_sessions for all to authenticated using(owner_user_id=(select auth.uid()) and exists(select 1 from public.members m where m.user_id=(select auth.uid()))) with check(owner_user_id=(select auth.uid()) and exists(select 1 from public.members m where m.user_id=(select auth.uid())));
revoke all on public.workout_sessions from anon;
grant select,insert,update,delete on public.workout_sessions to authenticated;
create index workout_sessions_owner_updated on public.workout_sessions(owner_user_id,updated_at);
create trigger health_version before update on public.workout_sessions for each row execute function public.health_version_guard();
create index workout_sessions_owner_date on public.workout_sessions(owner_user_id,(data->>'date')) where deleted_at is null;
create unique index nutrition_goals_owner_day_unique on public.nutrition_goals(owner_user_id,(data->>'date')) where deleted_at is null;
create unique index weight_logs_owner_day_unique on public.weight_logs(owner_user_id,(data->>'date')) where deleted_at is null;

create unique index health_profiles_owner_unique on public.health_profiles(owner_user_id) where deleted_at is null;
create trigger meal_image_owner before insert or update on public.meals for each row execute function public.health_image_owner_guard();

-- Aggregate meal/session JSON is an immutable-input snapshot; a single row write
-- makes parent + items atomic, without a partially saved meal or session.
create table public.food_catalog (
 source_key text primary key, source text not null check(source in ('usda','openfoodfacts')),
 data jsonb not null check(public.health_valid_food(data)), attribution text not null,
 updated_at timestamptz not null default now()
);
alter table public.food_catalog enable row level security;
create policy catalog_read on public.food_catalog for select to authenticated using(true);
grant select on public.food_catalog to authenticated;
revoke all on public.food_catalog from anon;

create table public.nutrition_analyses (
 id uuid primary key, owner_user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 image_path text not null check(split_part(image_path,'/',1)=owner_user_id::text),
 status text not null check(status in ('processing','complete','failed')), result jsonb, model text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.nutrition_analyses enable row level security;
create policy analysis_owner_read on public.nutrition_analyses for select to authenticated using(owner_user_id=(select auth.uid()));
create policy analysis_owner_delete on public.nutrition_analyses for delete to authenticated using(owner_user_id=(select auth.uid()));
grant select,delete on public.nutrition_analyses to authenticated;
revoke all on public.nutrition_analyses from anon;
create index nutrition_analyses_owner_time on public.nutrition_analyses(owner_user_id,created_at);

-- Service-only metrics: never contain food names, photos or profile data.
create table private.health_ai_usage (
 id uuid primary key default gen_random_uuid(), owner_user_id uuid references auth.users(id) on delete cascade,
 model text not null, elapsed_ms integer not null, tokens integer, outcome text not null,
 created_at timestamptz not null default now()
);
grant usage on schema private to service_role;
grant all on all tables in schema private to service_role;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('health-images','health-images',false,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy health_image_read on storage.objects for select to authenticated using(bucket_id='health-images' and (storage.foldername(name))[1]=(select auth.uid())::text and exists(select 1 from public.members m where m.user_id=(select auth.uid())));
create policy health_image_insert on storage.objects for insert to authenticated with check(bucket_id='health-images' and (storage.foldername(name))[1]=(select auth.uid())::text and exists(select 1 from public.members m where m.user_id=(select auth.uid())));
create policy health_image_delete on storage.objects for delete to authenticated using(bucket_id='health-images' and (storage.foldername(name))[1]=(select auth.uid())::text and exists(select 1 from public.members m where m.user_id=(select auth.uid())));

-- No realtime DELETE feed: private tombstones are updated rows, and refresh
-- on focus/reconnect covers hard deletion without broadcasting identifiers.

create table private.health_ai_settings (
 id boolean primary key default true check(id), model text not null default 'gemini-2.5-flash',
 enabled boolean not null default false, maintenance_token text not null default gen_random_uuid()::text,
 maintenance_url text, last_probe_at timestamptz, last_probe_ok boolean
);
insert into private.health_ai_settings(id) values(true);
grant all on private.health_ai_settings to service_role;
create or replace function public.health_service_settings() returns jsonb language sql security invoker set search_path='' as $$
 select jsonb_build_object('model',model,'enabled',enabled,'maintenanceToken',maintenance_token,'lastProbeOk',last_probe_ok) from private.health_ai_settings where id;
$$;
create or replace function public.health_probe_result(p_model text,p_ok boolean) returns void language sql security invoker set search_path='' as $$
 update private.health_ai_settings set model=p_model,enabled=p_ok,last_probe_at=now(),last_probe_ok=p_ok where id;
$$;
create or replace function public.health_log_ai(p_owner uuid,p_model text,p_elapsed integer,p_tokens integer,p_outcome text) returns void language sql security invoker set search_path='' as $$
 insert into private.health_ai_usage(owner_user_id,model,elapsed_ms,tokens,outcome) values(p_owner,p_model,p_elapsed,p_tokens,p_outcome);
$$;
create or replace function public.health_claim_analysis(p_id uuid,p_owner uuid,p_path text) returns text language plpgsql security invoker set search_path='' as $$
declare prior public.nutrition_analyses;
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_owner::text,1));
 if split_part(p_path,'/',1)<>p_owner::text then raise exception 'invalid_image'; end if;
 select * into prior from public.nutrition_analyses where id=p_id;
 if found then
  if prior.owner_user_id<>p_owner or prior.image_path<>p_path then raise exception 'invalid_input'; end if;
  if prior.status='complete' then return 'complete'; end if;
  if prior.status='processing' and prior.updated_at>now()-interval '90 seconds' then return 'busy'; end if;
 end if;
 if (select count(*) from public.nutrition_analyses where owner_user_id=p_owner and status='processing' and updated_at>now()-interval '90 seconds')>=2 then return 'busy'; end if;
 insert into public.nutrition_analyses(id,owner_user_id,image_path,status) values(p_id,p_owner,p_path,'processing')
 on conflict(id) do update set status='processing',updated_at=now();
 return 'claimed';
end;
$$;
create or replace function public.health_delete_module(p_owner uuid,p_module text) returns void language plpgsql security invoker set search_path='' as $$
declare t text;
begin
 if p_module not in ('all','nutrition','workouts') then raise exception 'invalid_module'; end if;
 if p_module in ('all','nutrition') then
 foreach t in array array['nutrition_goals','personal_foods','recipes','meals','water_logs','weight_logs','nutrition_analyses'] loop
 execute format('delete from public.%I where owner_user_id=$1',t) using p_owner; end loop;
 update public.health_profiles set data=jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(data,'{nutritionEnabled}','false'),'{age}','null'),'{height}','null'),'{weight}','null'),'{physiology}','null'),'{aiConsent}','false'),'{objective}','"maintain"'),version=version+1 where owner_user_id=p_owner;
 end if;
 if p_module in ('all','workouts') then
 delete from public.workout_sessions where owner_user_id=p_owner;delete from public.workout_plans where owner_user_id=p_owner;
 update public.health_profiles set data=jsonb_set(data,'{workoutsEnabled}','false'),version=version+1 where owner_user_id=p_owner;
 end if;
 if p_module='all' then delete from public.health_profiles where owner_user_id=p_owner; end if;
 delete from private.health_ai_usage where owner_user_id=p_owner;
end;
$$;
create or replace function public.health_request_maintenance(p_probe boolean default false) returns void language plpgsql security invoker set search_path='' as $$
declare settings private.health_ai_settings;
begin
 select * into settings from private.health_ai_settings where id;
 if settings.maintenance_url is not null then
 perform net.http_post(url:=settings.maintenance_url,headers:=jsonb_build_object('Content-Type','application/json','x-health-maintenance',settings.maintenance_token),body:=jsonb_build_object('probe',p_probe));
 end if;
end;
$$;
do $$ declare f text; begin
 foreach f in array array['health_service_settings()','health_probe_result(text,boolean)','health_log_ai(uuid,text,integer,integer,text)','health_claim_analysis(uuid,uuid,text)','health_delete_module(uuid,text)','health_request_maintenance(boolean)'] loop
 execute 'revoke all on function public.'||f||' from public,anon,authenticated';
 execute 'grant execute on function public.'||f||' to service_role';
 end loop;
end $$;
-- Enable a daily orphan cleanup only when the platform extensions exist.
do $$ begin
 if to_regnamespace('cron') is not null and to_regnamespace('net') is not null then
 perform cron.schedule('health-image-cleanup','17 3 * * *','select public.health_request_maintenance(false)');
 end if;
end $$;

-- USDA SR Legacy values fetched 2026-11-02; per 100 g; CC0.
insert into public.food_catalog(source_key,source,data,attribution) values('usda:171287','usda','{"id": "usda:171287", "name": "ביצה שלמה טרייה (נא)", "nameEn": "Egg, whole, raw, fresh", "per100": {"kcal": 143, "protein": 12.6, "carbs": 0.72, "fat": 9.51, "fiber": 0.0, "sugar": 0.37, "saturatedFat": 3.13, "sodium": 142}, "basis": "g", "source": "usda", "sourceId": "https://fdc.nal.usda.gov/food-details/171287/nutrients"}'::jsonb,'USDA FoodData Central / SR Legacy — CC0 1.0') on conflict(source_key) do nothing;
insert into public.food_catalog(source_key,source,data,attribution) values('usda:168878','usda','{"id": "usda:168878", "name": "אורז לבן ארוך מבושל", "nameEn": "Rice, white, long-grain, regular, enriched, cooked", "per100": {"kcal": 130, "protein": 2.69, "carbs": 28.2, "fat": 0.28, "fiber": 0.4, "sugar": 0.05, "saturatedFat": 0.077, "sodium": 1.0}, "basis": "g", "source": "usda", "sourceId": "https://fdc.nal.usda.gov/food-details/168878/nutrients"}'::jsonb,'USDA FoodData Central / SR Legacy — CC0 1.0') on conflict(source_key) do nothing;
insert into public.food_catalog(source_key,source,data,attribution) values('usda:171477','usda','{"id": "usda:171477", "name": "חזה עוף צלוי ללא עור", "nameEn": "Chicken, broilers or fryers, breast, meat only, cooked, roasted", "per100": {"kcal": 165, "protein": 31.0, "carbs": 0.0, "fat": 3.57, "fiber": 0.0, "sugar": 0.0, "saturatedFat": 1.01, "sodium": 74.0}, "basis": "g", "source": "usda", "sourceId": "https://fdc.nal.usda.gov/food-details/171477/nutrients"}'::jsonb,'USDA FoodData Central / SR Legacy — CC0 1.0') on conflict(source_key) do nothing;
insert into public.food_catalog(source_key,source,data,attribution) values('usda:173944','usda','{"id": "usda:173944", "name": "בננה טרייה", "nameEn": "Bananas, raw", "per100": {"kcal": 89.0, "protein": 1.09, "carbs": 22.8, "fat": 0.33, "fiber": 2.6, "sugar": 12.2, "saturatedFat": 0.112, "sodium": 1.0}, "basis": "g", "source": "usda", "sourceId": "https://fdc.nal.usda.gov/food-details/173944/nutrients"}'::jsonb,'USDA FoodData Central / SR Legacy — CC0 1.0') on conflict(source_key) do nothing;
insert into public.food_catalog(source_key,source,data,attribution) values('usda:171689','usda','{"id": "usda:171689", "name": "תפוח טרי ללא קליפה", "nameEn": "Apples, raw, without skin", "per100": {"kcal": 48.0, "protein": 0.27, "carbs": 12.8, "fat": 0.13, "fiber": 1.3, "sugar": 10.1, "saturatedFat": 0.021, "sodium": 0.0}, "basis": "g", "source": "usda", "sourceId": "https://fdc.nal.usda.gov/food-details/171689/nutrients"}'::jsonb,'USDA FoodData Central / SR Legacy — CC0 1.0') on conflict(source_key) do nothing;
insert into public.food_catalog(source_key,source,data,attribution) values('usda:171413','usda','{"id": "usda:171413", "name": "שמן זית", "nameEn": "Oil, olive, salad or cooking", "per100": {"kcal": 884, "protein": 0.0, "carbs": 0.0, "fat": 100, "fiber": 0.0, "sugar": 0.0, "saturatedFat": 13.8, "sodium": 2.0}, "basis": "g", "source": "usda", "sourceId": "https://fdc.nal.usda.gov/food-details/171413/nutrients"}'::jsonb,'USDA FoodData Central / SR Legacy — CC0 1.0') on conflict(source_key) do nothing;
insert into public.food_catalog(source_key,source,data,attribution) values('usda:171265','usda','{"id": "usda:171265", "name": "חלב מלא 3.25% מועשר בוויטמין D", "nameEn": "Milk, whole, 3.25% milkfat, with added vitamin D", "per100": {"kcal": 61.0, "protein": 3.15, "carbs": 4.8, "fat": 3.25, "fiber": 0.0, "sugar": 5.05, "saturatedFat": 1.86, "sodium": 43.0}, "basis": "g", "source": "usda", "sourceId": "https://fdc.nal.usda.gov/food-details/171265/nutrients"}'::jsonb,'USDA FoodData Central / SR Legacy — CC0 1.0') on conflict(source_key) do nothing;

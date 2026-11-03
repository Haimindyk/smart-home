-- Additive release. Apply only through the merged-main release workflow.
create table public.wellness_ai_jobs (
 id uuid primary key, owner_user_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in ('nutrition_photo','nutrition_text','coach','illustration')),
 fingerprint text not null, status text not null check(status in ('processing','complete','failed','applied','rejected')),
 result jsonb, error_code text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(octet_length(coalesce(result::text,'')) <= 200000)
);
alter table public.wellness_ai_jobs enable row level security;
create policy wellness_job_read on public.wellness_ai_jobs for select to authenticated using(owner_user_id=(select auth.uid()));
create policy wellness_job_delete on public.wellness_ai_jobs for delete to authenticated using(owner_user_id=(select auth.uid()));
revoke all on public.wellness_ai_jobs from public,anon,authenticated;
grant select,delete on public.wellness_ai_jobs to authenticated;
grant all on public.wellness_ai_jobs to service_role;
create index wellness_jobs_owner on public.wellness_ai_jobs(owner_user_id,created_at desc);

create table private.wellness_ai_daily_usage (
 day date not null, owner_user_id uuid not null references auth.users(id) on delete cascade,
 calls jsonb not null default '{}'::jsonb, reserved_neurons integer not null default 0,
 primary key(day,owner_user_id)
);
grant all on private.wellness_ai_daily_usage to service_role;

create table public.wellness_plan_versions (
 id uuid primary key default gen_random_uuid(), owner_user_id uuid not null references auth.users(id) on delete cascade,
 job_id uuid not null references public.wellness_ai_jobs(id) on delete cascade,
 plan_id uuid not null, previous_data jsonb, applied_data jsonb not null, applied_version integer not null,
 created_at timestamptz not null default now()
);
alter table public.wellness_plan_versions enable row level security;
create policy wellness_versions_read on public.wellness_plan_versions for select to authenticated using(owner_user_id=(select auth.uid()));
revoke all on public.wellness_plan_versions from public,anon,authenticated;
grant select on public.wellness_plan_versions to authenticated;
grant all on public.wellness_plan_versions to service_role;

create table public.wellness_exercise_illustrations (
 owner_user_id uuid not null references auth.users(id) on delete cascade, exercise_id text not null,
 image_path text not null, status text not null default 'pending_review' check(status in ('pending_review','reviewed')),
 created_at timestamptz not null default now(), primary key(owner_user_id,exercise_id),
 check(split_part(image_path,'/',1)=owner_user_id::text)
);
alter table public.wellness_exercise_illustrations enable row level security;
create policy wellness_illustrations_read on public.wellness_exercise_illustrations for select to authenticated using(owner_user_id=(select auth.uid()));
create policy wellness_illustrations_delete on public.wellness_exercise_illustrations for delete to authenticated using(owner_user_id=(select auth.uid()));
revoke all on public.wellness_exercise_illustrations from public,anon,authenticated;
grant select,delete on public.wellness_exercise_illustrations to authenticated;
grant all on public.wellness_exercise_illustrations to service_role;

create function public.wellness_claim_job(p_id uuid,p_owner uuid,p_kind text,p_fingerprint text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare prior public.wellness_ai_jobs; quota integer; reserve integer; used integer; day_key date=(now() at time zone 'UTC')::date;
begin
 if p_kind not in ('nutrition_photo','nutrition_text','coach','illustration') or length(p_fingerprint)<>64 then raise exception 'invalid_input'; end if;
 -- One account/day lock makes reservations atomic across users and concurrent calls.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('wellness:'||day_key::text,0));
 select * into prior from public.wellness_ai_jobs where id=p_id;
 if found then
  if prior.owner_user_id<>p_owner or prior.fingerprint<>p_fingerprint or prior.kind<>p_kind then raise exception 'request_conflict'; end if;
  if prior.status in ('complete','applied','rejected') then return jsonb_build_object('state',prior.status,'result',prior.result); end if;
  if prior.status='processing' and prior.updated_at>now()-interval '180 seconds' then return jsonb_build_object('state','busy'); end if;
 end if;
 if exists(select 1 from public.wellness_ai_jobs where owner_user_id=p_owner and status='processing' and updated_at>now()-interval '180 seconds')
 or (select count(*) from public.wellness_ai_jobs where status='processing' and updated_at>now()-interval '180 seconds')>=2 then return jsonb_build_object('state','busy'); end if;
 quota=case p_kind when 'nutrition_photo' then 5 when 'nutrition_text' then 20 when 'coach' then 10 else 5 end;
 reserve=case p_kind when 'nutrition_photo' then 350 when 'nutrition_text' then 150 when 'coach' then 450 else 200 end;
 select coalesce(sum(reserved_neurons),0) into used from private.wellness_ai_daily_usage where day=day_key;
 if used+reserve>8000 then return jsonb_build_object('state','quota'); end if;
 insert into private.wellness_ai_daily_usage(day,owner_user_id) values(day_key,p_owner) on conflict do nothing;
 if (select coalesce((calls->>p_kind)::integer,0) from private.wellness_ai_daily_usage where day=day_key and owner_user_id=p_owner)>=quota then return jsonb_build_object('state','quota'); end if;
 update private.wellness_ai_daily_usage set calls=jsonb_set(calls,array[p_kind],to_jsonb(coalesce((calls->>p_kind)::integer,0)+1)),reserved_neurons=reserved_neurons+reserve where day=day_key and owner_user_id=p_owner;
 insert into public.wellness_ai_jobs(id,owner_user_id,kind,fingerprint,status) values(p_id,p_owner,p_kind,p_fingerprint,'processing')
 on conflict(id) do update set status='processing',error_code=null,updated_at=now();
 return jsonb_build_object('state','claimed');
end;
$$;

create function public.wellness_apply_proposal(p_id uuid,p_owner uuid) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare job public.wellness_ai_jobs; change jsonb; current_plan public.workout_plans; next_version integer; plan_key uuid; ids jsonb='[]'::jsonb;
begin
 select * into job from public.wellness_ai_jobs where id=p_id and owner_user_id=p_owner for update;
 if not found or job.kind<>'coach' then raise exception 'not_found'; end if;
 if job.status='applied' then return jsonb_build_object('applied',true); end if;
 if job.status<>'complete' or jsonb_typeof(job.result->'changes')<>'array' or jsonb_array_length(job.result->'changes') not between 1 and 6 then raise exception 'invalid_input'; end if;
 for change in select value from jsonb_array_elements(job.result->'changes') order by value->>'id' loop
  plan_key=(change->>'id')::uuid;
  if change->>'expectedVersion' is null then
   insert into public.workout_plans(id,owner_user_id,data,last_mutation_id) values(plan_key,p_owner,change->'data',p_id);
   next_version=1; current_plan.data=null;
  else
   select * into current_plan from public.workout_plans where id=plan_key and owner_user_id=p_owner and deleted_at is null for update;
   if not found or current_plan.version<>(change->>'expectedVersion')::integer then raise exception 'version_conflict'; end if;
   next_version=current_plan.version+1;
   update public.workout_plans set data=change->'data',version=next_version,last_mutation_id=p_id where id=plan_key;
  end if;
  insert into public.wellness_plan_versions(owner_user_id,job_id,plan_id,previous_data,applied_data,applied_version) values(p_owner,p_id,plan_key,current_plan.data,change->'data',next_version);
  ids=ids||jsonb_build_array(plan_key);
 end loop;
 update public.wellness_ai_jobs set status='applied',updated_at=now() where id=p_id;
 return jsonb_build_object('applied',true,'planIds',ids);
end;
$$;

revoke all on function public.wellness_claim_job(uuid,uuid,text,text),public.wellness_apply_proposal(uuid,uuid) from public,anon,authenticated;
grant execute on function public.wellness_claim_job(uuid,uuid,text,text),public.wellness_apply_proposal(uuid,uuid) to service_role;

-- Service-only capability probe; no application data is exposed.
create function public.wellness_ai_ready() returns boolean language sql security invoker set search_path='' as $$ select true $$;
revoke all on function public.wellness_ai_ready() from public,anon,authenticated;
grant execute on function public.wellness_ai_ready() to service_role;

-- Public-domain generic foods. Real catalog matches take precedence over model estimates.
insert into public.food_catalog(source_key,source,data,attribution)
select 'wellness:'||(item->>'id'),'usda',jsonb_build_object('id','wellness:'||(item->>'id'),'name',item->>'name','nameEn',item->>'en','basis','g','source','usda','sourceId','https://fdc.nal.usda.gov/food-details/'||(item->>'fdc')||'/nutrients','per100',item->'per100'),'USDA FoodData Central — CC0; generic food, per 100 g'
from jsonb_array_elements('[
 {"id":"egg","fdc":"171287","name":"ביצה שלמה נא","en":"Egg whole raw","per100":{"kcal":143,"protein":12.6,"carbs":0.72,"fat":9.51,"fiber":0,"sugar":0.37,"saturatedFat":3.13,"sodium":142}},
 {"id":"rice","fdc":"168878","name":"אורז לבן מבושל","en":"White rice cooked","per100":{"kcal":130,"protein":2.69,"carbs":28.2,"fat":0.28,"fiber":0.4,"sugar":0.05,"saturatedFat":0.077,"sodium":1}},
 {"id":"chicken","fdc":"171477","name":"חזה עוף צלוי","en":"Chicken breast roasted","per100":{"kcal":165,"protein":31,"carbs":0,"fat":3.57,"fiber":0,"sugar":0,"saturatedFat":1.01,"sodium":74}},
 {"id":"banana","fdc":"173944","name":"בננה","en":"Banana raw","per100":{"kcal":89,"protein":1.09,"carbs":22.84,"fat":0.33,"fiber":2.6,"sugar":12.23,"saturatedFat":0.112,"sodium":1}}
]'::jsonb) item on conflict(source_key) do nothing;

-- Preserve the established module deletion transaction and include all AI content.
alter function public.health_delete_module(uuid,text) rename to health_delete_module_pre_wellness;
create function public.health_delete_module(p_owner uuid,p_module text) returns void
language plpgsql security invoker set search_path='' as $$
begin
 perform public.health_delete_module_pre_wellness(p_owner,p_module);
 if p_module in ('all','nutrition') then
  delete from public.wellness_ai_jobs where owner_user_id=p_owner and kind in ('nutrition_photo','nutrition_text');
 end if;
 if p_module in ('all','workouts') then
  delete from public.wellness_ai_jobs where owner_user_id=p_owner and kind in ('coach','illustration');
  delete from public.wellness_exercise_illustrations where owner_user_id=p_owner;
  update public.health_profiles set data=data-'trainingPreferences',version=version+1 where owner_user_id=p_owner;
 end if;
 if p_module='all' then delete from private.wellness_ai_daily_usage where owner_user_id=p_owner; end if;
end;
$$;
revoke all on function public.health_delete_module(uuid,text),public.health_delete_module_pre_wellness(uuid,text) from public,anon,authenticated;
grant execute on function public.health_delete_module(uuid,text),public.health_delete_module_pre_wellness(uuid,text) to service_role;

create function public.wellness_prune_usage() returns void language sql security invoker set search_path='' as $$
 delete from private.wellness_ai_daily_usage where day<(now() at time zone 'UTC')::date-30;
$$;
revoke all on function public.wellness_prune_usage() from public,anon,authenticated;
grant execute on function public.wellness_prune_usage() to service_role;

-- A module deletion cannot be followed by a late inference recreating its image row.
create function public.wellness_publish_illustration(p_id uuid,p_owner uuid,p_exercise text,p_path text) returns void
language plpgsql security invoker set search_path='' as $$
begin
 perform 1 from public.wellness_ai_jobs where id=p_id and owner_user_id=p_owner and kind='illustration' and status='processing' for update;
 if not found then raise exception 'request_conflict'; end if;
 insert into public.wellness_exercise_illustrations(owner_user_id,exercise_id,image_path,status) values(p_owner,p_exercise,p_path,'pending_review')
 on conflict(owner_user_id,exercise_id) do update set image_path=excluded.image_path,status='pending_review';
end;
$$;
revoke all on function public.wellness_publish_illustration(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.wellness_publish_illustration(uuid,uuid,text,text) to service_role;

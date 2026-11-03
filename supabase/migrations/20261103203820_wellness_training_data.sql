-- Training is a separate opt-in from inference. No retrospective harvesting.
create table public.wellness_training_consents (
 owner_user_id uuid primary key references auth.users(id) on delete cascade,
 subject_group uuid not null default gen_random_uuid(),
 enabled boolean not null default false,
 policy_version text not null check(policy_version='wellness-training-v1'),
 updated_at timestamptz not null default now()
);
alter table public.wellness_training_consents enable row level security;
create policy training_consent_read on public.wellness_training_consents for select to authenticated using(owner_user_id=(select auth.uid()));
revoke all on public.wellness_training_consents from public,anon,authenticated;
grant select on public.wellness_training_consents to authenticated;
grant all on public.wellness_training_consents to service_role;
create table public.wellness_training_examples (
 id uuid primary key default gen_random_uuid(), owner_user_id uuid not null references auth.users(id) on delete cascade,
 task text not null check(task in ('nutrition_text','nutrition_photo','coach_program')),
 source_id uuid not null, example jsonb not null check(jsonb_typeof(example)='object' and octet_length(example::text)<=150000),
 image_path text check(image_path is null or split_part(image_path,'/',1)=owner_user_id::text),
 created_at timestamptz not null default now()
);
alter table public.wellness_training_examples enable row level security;
create policy training_examples_read on public.wellness_training_examples for select to authenticated using(owner_user_id=(select auth.uid()));
revoke all on public.wellness_training_examples from public,anon,authenticated;
grant select on public.wellness_training_examples to authenticated;
grant all on public.wellness_training_examples to service_role;
create index training_examples_owner on public.wellness_training_examples(owner_user_id,created_at);
create index training_examples_source on public.wellness_training_examples(source_id,owner_user_id);

create function public.wellness_training_consent(p_owner uuid,p_enabled boolean) returns void language plpgsql security invoker set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('wellness-training:'||p_owner::text,0));
 insert into public.wellness_training_consents(owner_user_id,enabled,policy_version) values(p_owner,p_enabled,'wellness-training-v1')
 on conflict(owner_user_id) do update set enabled=excluded.enabled,updated_at=now();
 if not p_enabled then delete from public.wellness_training_examples where owner_user_id=p_owner; end if;
end;
$$;
create function public.wellness_training_submit(p_owner uuid,p_task text,p_source uuid,p_example jsonb,p_image text default null) returns uuid language plpgsql security invoker set search_path='' as $$
declare example_id uuid;
begin
 perform pg_advisory_xact_lock(hashtextextended('wellness-training:'||p_owner::text,0));
 if not exists(select 1 from public.wellness_training_consents where owner_user_id=p_owner and enabled) then raise exception 'training_consent_required';end if;
 if (select count(*) from public.wellness_training_examples where owner_user_id=p_owner)>=200 then raise exception 'training_limit';end if;
 insert into public.wellness_training_examples(owner_user_id,task,source_id,example,image_path) values(p_owner,p_task,p_source,p_example,p_image) returning id into example_id;
 return example_id;
end;
$$;
-- Keep the established deletion transaction, including inference content.
alter function public.health_delete_module(uuid,text) rename to health_delete_module_pre_training;
create function public.health_delete_module(p_owner uuid,p_module text) returns void language plpgsql security invoker set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('wellness-training:'||p_owner::text,0));
 perform public.health_delete_module_pre_training(p_owner,p_module);
 if p_module in ('all','nutrition') then delete from public.wellness_training_examples where owner_user_id=p_owner and task in ('nutrition_text','nutrition_photo');end if;
 if p_module in ('all','workouts') then delete from public.wellness_training_examples where owner_user_id=p_owner and task='coach_program';end if;
 if p_module='all' then delete from public.wellness_training_consents where owner_user_id=p_owner;end if;
end;
$$;
revoke all on function public.wellness_training_consent(uuid,boolean), public.wellness_training_submit(uuid,text,uuid,jsonb,text), public.health_delete_module(uuid,text),public.health_delete_module_pre_training(uuid,text) from public,anon,authenticated;
grant execute on function public.wellness_training_consent(uuid,boolean), public.wellness_training_submit(uuid,text,uuid,jsonb,text), public.health_delete_module(uuid,text),public.health_delete_module_pre_training(uuid,text) to service_role;

-- Own adapters can use a different base model. Reserve more than the hosted path.
create function public.wellness_claim_owned_job(p_id uuid,p_owner uuid,p_kind text,p_fingerprint text) returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb; reserve integer; used integer; day_key date=(now() at time zone 'UTC')::date;
begin
 perform pg_advisory_xact_lock(hashtextextended('wellness:'||day_key::text,0));
 if exists(select 1 from public.wellness_ai_jobs where id=p_id and status in ('complete','applied','rejected')) then return public.wellness_claim_job(p_id,p_owner,p_kind,p_fingerprint);end if;
 select coalesce(sum(reserved_neurons),0) into used from private.wellness_ai_daily_usage where day=day_key;
 if used+1600>8000 then return jsonb_build_object('state','quota');end if;
 result=public.wellness_claim_job(p_id,p_owner,p_kind,p_fingerprint);
 if result->>'state'='claimed' then
  reserve=case p_kind when 'nutrition_photo' then 350 when 'nutrition_text' then 150 when 'coach' then 450 else 200 end;
  update private.wellness_ai_daily_usage set reserved_neurons=reserved_neurons+1600-reserve where day=day_key and owner_user_id=p_owner;
 end if;
 return result;
end;
$$;
revoke all on function public.wellness_claim_owned_job(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.wellness_claim_owned_job(uuid,uuid,text,text) to service_role;

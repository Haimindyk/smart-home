-- Owner-only conversations. Chat uses the same account-wide free budget.
alter table public.wellness_ai_jobs drop constraint wellness_ai_jobs_kind_check;
alter table public.wellness_ai_jobs add constraint wellness_ai_jobs_kind_check check(kind in ('nutrition_photo','nutrition_text','coach','illustration','chat'));
create or replace function public.wellness_claim_job(p_id uuid,p_owner uuid,p_kind text,p_fingerprint text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare prior public.wellness_ai_jobs; quota integer; reserve integer; used integer; day_key date=(now() at time zone 'UTC')::date;
begin
 if p_kind not in ('nutrition_photo','nutrition_text','coach','illustration','chat') or length(p_fingerprint)<>64 then raise exception 'invalid_input'; end if;
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
 quota=case p_kind when 'nutrition_photo' then 5 when 'nutrition_text' then 20 when 'coach' then 10 when 'chat' then 40 else 5 end;
 reserve=case p_kind when 'nutrition_photo' then 350 when 'nutrition_text' then 150 when 'coach' then 450 when 'chat' then 200 else 200 end;
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


create table public.wellness_chat_threads (
 owner_user_id uuid primary key references auth.users(id) on delete cascade,
 generation uuid not null default gen_random_uuid(), version integer not null default 0 check(version>=0), updated_at timestamptz not null default now()
);
create table public.wellness_chat_turns (
 id uuid primary key references public.wellness_ai_jobs(id) on delete cascade,
 owner_user_id uuid not null references auth.users(id) on delete cascade,
 generation uuid not null, user_text text not null check(length(user_text) between 1 and 2000),
 answer jsonb not null check(jsonb_typeof(answer)='object' and octet_length(answer::text)<=20000),
 shared_diary boolean not null default false, created_at timestamptz not null default now()
);
create index wellness_chat_owner_recent on public.wellness_chat_turns(owner_user_id,created_at desc,id);
alter table public.wellness_chat_threads enable row level security;
alter table public.wellness_chat_turns enable row level security;
create policy chat_threads_read on public.wellness_chat_threads for select to authenticated using(owner_user_id=(select auth.uid()));
create policy chat_turns_read on public.wellness_chat_turns for select to authenticated using(owner_user_id=(select auth.uid()));
revoke all on public.wellness_chat_threads,public.wellness_chat_turns from public,anon,authenticated;
grant select on public.wellness_chat_threads,public.wellness_chat_turns to authenticated;
grant all on public.wellness_chat_threads,public.wellness_chat_turns to service_role;

create function public.wellness_chat_state(p_owner uuid) returns jsonb language plpgsql security invoker set search_path='' as $$
declare thread public.wellness_chat_threads; used integer;
begin
 insert into public.wellness_chat_threads(owner_user_id) values(p_owner) on conflict do nothing;
 select * into thread from public.wellness_chat_threads where owner_user_id=p_owner;
 select coalesce((calls->>'chat')::integer,0) into used from private.wellness_ai_daily_usage where owner_user_id=p_owner and day=(now() at time zone 'UTC')::date;
 return jsonb_build_object('generation',thread.generation,'version',thread.version,'used',coalesce(used,0),'limit',40);
end;
$$;
create function public.wellness_chat_claim(p_id uuid,p_owner uuid,p_generation uuid,p_version integer,p_fingerprint text) returns jsonb language plpgsql security invoker set search_path='' as $$
declare thread public.wellness_chat_threads; prior public.wellness_ai_jobs;
begin
 perform pg_advisory_xact_lock(hashtextextended('wellness-chat:'||p_owner::text,0));
 select * into thread from public.wellness_chat_threads where owner_user_id=p_owner for update;
 if not found or thread.generation<>p_generation then raise exception 'version_conflict';end if;
 select * into prior from public.wellness_ai_jobs where id=p_id;
 if found and prior.status='complete' then return public.wellness_claim_job(p_id,p_owner,'chat',p_fingerprint);end if;
 if thread.version<>p_version then raise exception 'version_conflict';end if;
 return public.wellness_claim_job(p_id,p_owner,'chat',p_fingerprint);
end;
$$;
create function public.wellness_chat_publish(p_id uuid,p_owner uuid,p_generation uuid,p_version integer,p_message text,p_answer jsonb,p_diary boolean) returns jsonb language plpgsql security invoker set search_path='' as $$
declare thread public.wellness_chat_threads; job public.wellness_ai_jobs; saved_result jsonb;
begin
 perform pg_advisory_xact_lock(hashtextextended('wellness-chat:'||p_owner::text,0));
 select * into thread from public.wellness_chat_threads where owner_user_id=p_owner for update;
 select * into job from public.wellness_ai_jobs where id=p_id and owner_user_id=p_owner and kind='chat' for update;
 if not found then raise exception 'request_conflict';end if;
 if thread.generation is distinct from p_generation then raise exception 'version_conflict';end if;
 if job.status='complete' then return job.result;end if;
 if job.status<>'processing' or thread.version<>p_version then raise exception 'version_conflict';end if;
 insert into public.wellness_chat_turns(id,owner_user_id,generation,user_text,answer,shared_diary) values(p_id,p_owner,p_generation,p_message,p_answer,p_diary);
 update public.wellness_chat_threads set version=version+1,updated_at=now() where owner_user_id=p_owner;
 saved_result=jsonb_build_object('id',p_id,'answer',p_answer,'version',p_version+1,'generation',p_generation);
 update public.wellness_ai_jobs set status='complete',result=saved_result,updated_at=now() where id=p_id;
 return saved_result;
end;
$$;
create function public.wellness_chat_clear(p_owner uuid) returns void language plpgsql security invoker set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('wellness-chat:'||p_owner::text,0));
 update public.wellness_chat_threads set generation=gen_random_uuid(),version=0,updated_at=now() where owner_user_id=p_owner;
 delete from public.wellness_ai_jobs where owner_user_id=p_owner and kind='chat';
end;
$$;
alter function public.health_delete_module(uuid,text) rename to health_delete_module_pre_chat;
create function public.health_delete_module(p_owner uuid,p_module text) returns void language plpgsql security invoker set search_path='' as $$
begin
 perform public.wellness_chat_clear(p_owner);
 perform public.health_delete_module_pre_chat(p_owner,p_module);
 if p_module='all' then delete from public.wellness_chat_threads where owner_user_id=p_owner;end if;
end;
$$;
revoke all on function public.wellness_chat_state(uuid),public.wellness_chat_claim(uuid,uuid,uuid,integer,text),public.wellness_chat_publish(uuid,uuid,uuid,integer,text,jsonb,boolean),public.wellness_chat_clear(uuid),public.health_delete_module(uuid,text),public.health_delete_module_pre_chat(uuid,text) from public,anon,authenticated;
grant execute on function public.wellness_chat_state(uuid),public.wellness_chat_claim(uuid,uuid,uuid,integer,text),public.wellness_chat_publish(uuid,uuid,uuid,integer,text,jsonb,boolean),public.wellness_chat_clear(uuid),public.health_delete_module(uuid,text),public.health_delete_module_pre_chat(uuid,text) to service_role;

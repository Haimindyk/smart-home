-- Photo normalization explicitly uses the explicitly selected larger hosted model.
-- Reserve conservatively while retaining the same shared 8000-neuron budget.
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
 reserve=case p_kind when 'nutrition_photo' then 650 when 'nutrition_text' then 150 when 'coach' then 450 when 'chat' then 200 else 200 end;
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

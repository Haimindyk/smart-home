-- Some managed pg_net tables retain extension-owner PUBLIC grants. Never
-- transport a reusable credential through that queue. Issue an action-bound,
-- single-use token instead; only its SHA-256 digest is retained privately.
create table private.health_maintenance_requests (
 token_hash text primary key, probe boolean not null, expires_at timestamptz not null
);
revoke all on private.health_maintenance_requests from public,anon,authenticated;
grant all on private.health_maintenance_requests to service_role;
create or replace function public.health_accept_maintenance(p_token text,p_probe boolean) returns boolean language plpgsql security invoker set search_path='' as $$
declare accepted text;
begin
 delete from private.health_maintenance_requests
 where token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex') and probe=p_probe and expires_at>now()
 returning token_hash into accepted;
 return accepted is not null;
end;
$$;
revoke all on function public.health_accept_maintenance(text,boolean) from public,anon,authenticated;
grant execute on function public.health_accept_maintenance(text,boolean) to service_role;
create or replace function public.health_service_settings() returns jsonb language sql security invoker set search_path='' as $$
 select jsonb_build_object('model',model,'enabled',enabled,'lastProbeOk',last_probe_ok) from private.health_ai_settings where id;
$$;
create or replace function public.health_request_maintenance(p_probe boolean default false) returns void language plpgsql security invoker set search_path='' as $$
declare settings private.health_ai_settings; token text=gen_random_uuid()::text||gen_random_uuid()::text;
begin
 select * into settings from private.health_ai_settings where id;
 delete from private.health_maintenance_requests where expires_at<now();
 if settings.maintenance_url is not null then
 insert into private.health_maintenance_requests values(encode(sha256(convert_to(token,'UTF8')),'hex'),p_probe,now()+interval '2 minutes');
 perform net.http_post(url:=settings.maintenance_url,headers:=jsonb_build_object('Content-Type','application/json','x-health-maintenance',token),body:=jsonb_build_object('probe',p_probe),timeout_milliseconds:=65000);
 end if;
end;
$$;
revoke all on function public.health_request_maintenance(boolean) from public,anon,authenticated;
grant execute on function public.health_request_maintenance(boolean) to service_role;
-- The legacy reusable token is rotated and is no longer accepted or sent.
update private.health_ai_settings set maintenance_token=gen_random_uuid()::text where id;

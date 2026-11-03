-- pg_net defaults to 5s; image-model probes need a bounded longer request.
create or replace function public.health_request_maintenance(p_probe boolean default false) returns void language plpgsql security invoker set search_path='' as $$
declare settings private.health_ai_settings;
begin
 select * into settings from private.health_ai_settings where id;
 if settings.maintenance_url is not null then
 perform net.http_post(url:=settings.maintenance_url,headers:=jsonb_build_object('Content-Type','application/json','x-health-maintenance',settings.maintenance_token),body:=jsonb_build_object('probe',p_probe),timeout_milliseconds:=65000);
 end if;
end;
$$;
revoke all on function public.health_request_maintenance(boolean) from public,anon,authenticated;
grant execute on function public.health_request_maintenance(boolean) to service_role;

-- pg_net request headers contain a private maintenance credential.
-- Keep queue access server-only even on projects with permissive old grants.
do $$ begin
 if to_regclass('net.http_request_queue') is not null then
  revoke all on table net.http_request_queue from public,anon,authenticated;
  grant all on table net.http_request_queue to service_role;
 end if;
end $$;
-- Rotate after restricting the queue so any previously queued token expires.
update private.health_ai_settings set maintenance_token=gen_random_uuid()::text where id;

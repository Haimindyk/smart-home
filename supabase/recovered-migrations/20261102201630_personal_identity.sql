-- Deploy together with server-PIN IdentityGate. Never run this migration
-- against an old client that still compares plaintext PINs in the browser.
create schema if not exists private;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
grant usage on schema extensions to service_role;
-- Older fresh installs put pgcrypto in public. Resolve its actual namespace
-- without relocating the extension or breaking other functions' dependencies.
do $wrap$ declare ns text; begin
 select n.nspname into ns from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='pgcrypto';
 execute format($fn$create function private.health_hmac(d text,k text,t text) returns bytea language sql set search_path='' as 'select %I.hmac(d,k,t)'$fn$,ns);
 execute format($fn$create function private.health_crypt(d text,s text) returns text language sql set search_path='' as 'select %I.crypt(d,s)'$fn$,ns);
 execute format($fn$create function private.health_gen_salt(t text,c integer) returns text language sql set search_path='' as 'select %I.gen_salt(t,c)'$fn$,ns);
 execute format($fn$create function private.health_random_bytes(c integer) returns bytea language sql set search_path='' as 'select %I.gen_random_bytes(c)'$fn$,ns);
end $wrap$;
create table private.health_login_secret(id boolean primary key default true check(id), secret text not null);
insert into private.health_login_secret(secret) values(encode(private.health_random_bytes(32),'hex'));
create table private.member_credentials (
 member_id uuid primary key references public.members(id) on delete cascade,
 fingerprint text not null unique, pin_hash text not null
);
insert into private.member_credentials(member_id,fingerprint,pin_hash)
select id,encode(private.health_hmac(pin,(select secret from private.health_login_secret),'sha256'),'hex'),private.health_crypt(pin,private.health_gen_salt('bf',8))
from public.members where pin is not null;
update public.members set pin=null where pin is not null;
create table private.pin_attempts (window_start timestamptz primary key, attempts integer not null);
grant usage on schema private to service_role;
grant all on all tables in schema private to service_role;
revoke all on all tables in schema private from public,anon,authenticated;

create or replace function public.verify_health_pin(p_pin text) returns table(id uuid,email text,user_id uuid)
language plpgsql security invoker set search_path='' as $$
declare attempts integer; slot timestamptz=date_trunc('minute',now());
begin
 if p_pin !~ '^\d{4}$' then return; end if;
 insert into private.pin_attempts values(slot,1) on conflict(window_start) do update set attempts=private.pin_attempts.attempts+1 returning pin_attempts.attempts into attempts;
 delete from private.pin_attempts where window_start < now()-interval '1 day';
 if attempts>30 then raise exception 'rate_limited'; end if;
 return query select m.id,m.email,m.user_id from private.member_credentials c join public.members m on m.id=c.member_id
 where c.fingerprint=encode(private.health_hmac(p_pin,(select secret from private.health_login_secret),'sha256'),'hex') and c.pin_hash=private.health_crypt(p_pin,c.pin_hash);
end;
$$;
revoke all on function public.verify_health_pin(text) from public,anon,authenticated;
grant execute on function public.verify_health_pin(text) to service_role;

-- Preserve the production pepper: rotating it would break synthetic account
-- passwords. A new installation gets a service-only equivalent.
do $outer$ begin
 if to_regprocedure('public.get_pin_login_pepper()') is null then
 execute $fn$create function public.get_pin_login_pepper() returns text language sql security definer set search_path='' as 'select secret from private.health_login_secret where id'$fn$;
 end if;
end $outer$;
revoke all on function public.get_pin_login_pepper() from public,anon,authenticated;
grant execute on function public.get_pin_login_pepper() to service_role;

create or replace function public.health_protect_member_identity() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user not in ('postgres','supabase_admin','service_role') then
 if tg_op='INSERT' then raise exception 'use_member_registration'; end if;
 if new.user_id is distinct from old.user_id or new.email is distinct from old.email or new.pin is distinct from old.pin then raise exception 'protected_identity'; end if;
 end if;
 return new;
end;
$$;
create trigger protect_member_identity before insert or update on public.members for each row execute function public.health_protect_member_identity();
revoke insert on public.members from anon,authenticated;
revoke select on public.members from anon,authenticated;
grant select(id,email,user_id,display_name,avatar_emoji,color,locale,created_at,updated_at,avatar_photo_url,is_ai_companion_target,last_chat_at,gender) on public.members to anon,authenticated;

-- Service-only registration: the Edge Function validates the current JWT.
create or replace function public.register_health_member(p_name text,p_pin text,p_emoji text,p_color text)
returns uuid language plpgsql security invoker set search_path='' as $$
declare member_id uuid=gen_random_uuid();
begin
 if length(trim(p_name)) not between 1 and 100 or p_pin !~ '^\d{4}$' or length(p_emoji)>20 or p_color !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'invalid_member'; end if;
 insert into public.members(id,email,display_name,avatar_emoji,color) values(member_id,member_id::text||'@members.kh.local',trim(p_name),p_emoji,p_color);
 insert into private.member_credentials values(member_id,encode(private.health_hmac(p_pin,(select secret from private.health_login_secret),'sha256'),'hex'),private.health_crypt(p_pin,private.health_gen_salt('bf',8)));
 return member_id;
end;
$$;
revoke all on function public.register_health_member(text,text,text,text) from public,anon,authenticated;
grant execute on function public.register_health_member(text,text,text,text) to service_role;

-- Public sign-up must never claim a household identity just by knowing its email.
-- Only server-created PIN accounts carry this immutable app_metadata marker.
create or replace function public.link_member_on_signup() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.raw_app_meta_data->>'health_pin_account'='true' then
 update public.members set user_id=new.id where lower(email)=lower(new.email) and user_id is null;
 end if;
 return new;
end;
$$;
revoke all on function public.link_member_on_signup() from public,anon,authenticated;

-- This table exists when the additive server release preceded this migration.
do $$ begin
 if to_regclass('public.health_release_state') is not null then
 update public.health_release_state set personal_access_ready=true where id;
 end if;
end $$;

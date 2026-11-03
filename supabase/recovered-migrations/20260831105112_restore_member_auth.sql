create or replace function public.link_member_on_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.members
    set user_id = new.id
    where lower(email) = lower(new.email) and user_id is null;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.link_member_on_signup();

create or replace function public.current_member_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.members where user_id = auth.uid();
$$;

create or replace function public.get_pin_login_pepper()
returns text
language sql
stable
security definer
set search_path = public, vault
as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'pin_login_pepper';
$$;

revoke all on function public.get_pin_login_pepper() from public, anon, authenticated;
grant execute on function public.get_pin_login_pepper() to service_role;
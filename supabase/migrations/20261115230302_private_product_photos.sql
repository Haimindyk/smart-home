-- Private product images use the existing owner-scoped bucket and food JSON.
create or replace function public.health_image_owner_guard() returns trigger
language plpgsql set search_path='' as $$
declare path text;
begin
 for path in
  select new.data->>'imagePath'
  union all
  select item->'food'->>'imagePath' from jsonb_array_elements(
   case when jsonb_typeof(new.data->'items')='array' then new.data->'items' else '[]'::jsonb end
  ) item
 loop
  if path is not null and (split_part(path,'/',1) <> new.owner_user_id::text or length(path)>500 or position('..' in path)>0) then
   raise exception 'invalid_image_owner';
  end if;
 end loop;
 return new;
end;
$$;
drop trigger if exists product_image_owner on public.personal_foods;
create trigger product_image_owner before insert or update on public.personal_foods
 for each row execute function public.health_image_owner_guard();
drop trigger if exists recipe_image_owner on public.recipes;
create trigger recipe_image_owner before insert or update on public.recipes
 for each row execute function public.health_image_owner_guard();

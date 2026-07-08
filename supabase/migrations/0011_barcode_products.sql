-- A community-taught barcode -> product-name cache. Open Food Facts has thin
-- coverage for Israeli-local products (729-prefixed barcodes), so once any
-- family member types a name for a barcode no lookup recognized, save it
-- here — every family member, and every future scan of that same barcode,
-- gets automatic recognition from then on instead of re-asking.

create table public.barcode_products (
  barcode       text primary key,
  product_name  text not null,
  created_by    uuid references public.members(id) on delete set null,
  created_at    timestamptz not null default now()
);

alter table public.barcode_products enable row level security;

create policy "members full access to barcode_products" on public.barcode_products
  for all using (public.is_member()) with check (public.is_member());

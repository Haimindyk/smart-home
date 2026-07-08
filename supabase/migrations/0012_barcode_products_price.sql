-- Retail price alongside the product name, captured from the same chain
-- price-transparency feeds — lets a future feature simulate a shopping
-- list's total cost instead of just naming items.
alter table public.barcode_products add column if not exists price numeric;
alter table public.barcode_products add column if not exists currency text not null default 'ILS';

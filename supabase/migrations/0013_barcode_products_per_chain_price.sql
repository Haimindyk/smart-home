-- Track each chain's price in its own column instead of a single shared
-- "price" — the same barcode can (and often does) cost differently at
-- Shufersal vs. Rami Levy, and overwriting one with the other would silently
-- lose data instead of ever creating a duplicate row (barcode stays the
-- primary key either way).
alter table public.barcode_products rename column price to price_shufersal;
alter table public.barcode_products add column if not exists price_rami_levy numeric;

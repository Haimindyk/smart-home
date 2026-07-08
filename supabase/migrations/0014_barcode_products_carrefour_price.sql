-- Third chain's price, same pattern as Shufersal/Rami Levy: its own column,
-- never a duplicate barcode row.
alter table public.barcode_products add column if not exists price_carrefour numeric;

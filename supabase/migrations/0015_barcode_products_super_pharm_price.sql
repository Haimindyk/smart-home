-- Fourth chain's price, same pattern as the others: its own column, never a
-- duplicate barcode row.
alter table public.barcode_products add column if not exists price_super_pharm numeric;

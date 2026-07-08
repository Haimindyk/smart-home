-- Fuzzy product-name search, used by the price-comparison feature to find a
-- substitute when a shopping-list item has no exact barcode match at a given
-- chain. pg_trgm's `%` operator + similarity() gives real trigram-based
-- title similarity without needing per-item brand/category/size fields we
-- don't have — the closest thing to "similar product" our data supports.
create extension if not exists pg_trgm;

create index if not exists barcode_products_product_name_trgm_idx
  on public.barcode_products using gin (product_name gin_trgm_ops);

-- Returns whole rows (including every price_* column) so adding a new chain
-- later needs no change here — callers just read the new column off the result.
create or replace function public.search_barcode_products(p_query text, p_limit int default 5)
returns setof public.barcode_products
language sql
stable
as $$
  select *
  from public.barcode_products
  where product_name % p_query
  order by similarity(product_name, p_query) desc
  limit p_limit;
$$;

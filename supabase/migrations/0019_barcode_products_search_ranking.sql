-- The previous "try similarity(), fall back to word_similarity() only if
-- that finds nothing" approach had a gap: similarity() can return a small
-- number of low-relevance rows (not zero), which blocks the fallback from
-- ever running even though word_similarity() would have ranked the real
-- match first. E.g. querying "חלב" (milk) found only "מקציף חלב" (a milk
-- frother, coincidentally short and scoring high on whole-string
-- similarity) and stopped there, never considering actual milk cartons.
--
-- Fixed by always ranking by word_similarity() — verified it still puts the
-- correct product first even for multi-word queries sharing a generic
-- suffix with unrelated products (e.g. "חלב 3% ליטר" correctly outranks
-- "שמן חמניות 3 ליטר" despite both containing "3 ליטר").
create or replace function public.search_barcode_products(p_query text, p_limit int default 5)
returns setof public.barcode_products
language sql
stable
as $$
  select *
  from public.barcode_products
  where product_name % p_query or p_query <% product_name
  order by word_similarity(p_query, product_name) desc, similarity(product_name, p_query) desc
  limit p_limit;
$$;

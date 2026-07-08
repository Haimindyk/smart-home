-- similarity() (the % operator) compares whole strings and handles
-- multi-word queries well — "חלב 3% ליטר" correctly ranks the one matching
-- milk product above unrelated "3 ליטר" products. But it badly under-scores
-- a short single-word query against a much longer catalog name — "נוטלה"
-- scored a Nutella product only ~0.24-0.32, below the 0.3 cutoff, even
-- though the word matches perfectly.
--
-- word_similarity() (the <% operator) fixes that (scores it 1.0) by looking
-- for the best-matching contiguous extent within the longer string instead
-- of penalizing for its extra length — but blending the two scores lets
-- word_similarity's looser matching pull in noise on multi-word queries
-- (e.g. matching just "3 ליטר" while ignoring "חלב" entirely).
--
-- So: try the precise similarity() search first; only fall back to the
-- looser word_similarity() search when that finds nothing at all.
create or replace function public.search_barcode_products(p_query text, p_limit int default 5)
returns setof public.barcode_products
language plpgsql
stable
as $$
begin
  return query
    select *
    from public.barcode_products
    where product_name % p_query
    order by similarity(product_name, p_query) desc
    limit p_limit;

  if not found then
    return query
      select *
      from public.barcode_products
      where p_query <% product_name
      order by word_similarity(p_query, product_name) desc
      limit p_limit;
  end if;
end;
$$;

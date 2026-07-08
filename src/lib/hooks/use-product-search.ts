"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { stripShoppingFillerWords } from "@/lib/nlp/strip-shopping-filler";
import type { BarcodeProduct } from "@/types/domain";

/** Debounced fuzzy search against the barcode_products cache — lets quick-add
 * offer real products (with known prices across chains) instead of only
 * free text. Returns nothing until the query has a couple of characters. */
export function useProductSearch(query: string, enabled: boolean) {
  const [results, setResults] = useState<BarcodeProduct[]>([]);
  // Quick-add's own placeholder suggests phrasing like "לקנות חלב" — strip
  // that kind of filler before searching, same as the price-comparison matcher.
  const trimmed = stripShoppingFillerWords(query);
  const active = enabled && trimmed.length >= 2;

  useEffect(() => {
    if (!active) return;
    let cancelled = false;
    const timer = setTimeout(() => {
      const supabase = createClient();
      supabase.rpc("search_barcode_products", { p_query: trimmed, p_limit: 6 }).then(({ data }) => {
        if (!cancelled) setResults(data ?? []);
      });
    }, 250);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [trimmed, active]);

  return active ? results : [];
}

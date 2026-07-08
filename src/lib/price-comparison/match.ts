import { createClient } from "@/lib/supabase/client";
import { stripShoppingFillerWords } from "@/lib/nlp/strip-shopping-filler";
import { expandSynonymQueries } from "@/lib/nlp/product-synonyms";
import type { BarcodeProduct } from "@/types/domain";
import type { BasketInput } from "./types";

/** The barcode scanner stores its code inline in the item's notes (e.g.
 * "ברקוד: 7290012345678") rather than as a structured column — pull it back
 * out so an exact match can be tried before falling back to fuzzy title
 * search. */
function extractBarcode(notes: string | null | undefined): string | null {
  if (!notes) return null;
  const m = notes.match(/\b(\d{8,14})\b/);
  return m ? m[1] : null;
}

export type MatchResult =
  | { kind: "exact"; product: BarcodeProduct }
  /** Ranked best-first — different chains can carry different barcodes for
   * "the same" product (a generic jar vs. a single-serve snack pack, say),
   * so each chain picks the best-ranked candidate *it actually has a price
   * for* rather than being stuck with one globally-best textual match that
   * might only be sold at one chain. */
  | { kind: "fuzzy"; candidates: BarcodeProduct[] }
  | { kind: "none" };

/**
 * Finds barcode_products candidates for one shopping-list item: an exact
 * barcode lookup first (if the item was scanned), then a trigram
 * title-similarity search as a stand-in for "same brand/size/category" —
 * matching on those individually isn't possible without per-item structured
 * attributes, which our imported chain data doesn't carry.
 */
export async function matchBasketItem(item: BasketInput): Promise<MatchResult> {
  const supabase = createClient();
  const barcode = extractBarcode(item.notes);

  if (barcode) {
    const { data } = await supabase.from("barcode_products").select("*").eq("barcode", barcode).maybeSingle();
    if (data) return { kind: "exact", product: data };
  }

  // Some product categories are named completely differently from chain to
  // chain (e.g. Shufersal sells body wash as "תחליב רחצה" while another chain
  // calls the same category "סבון גוף") — trigram similarity can't bridge
  // two phrasings sharing no common words, so a known-synonym query also
  // searches under its alternate phrasings and the results are merged.
  const queries = expandSynonymQueries(stripShoppingFillerWords(item.title));
  const results = await Promise.all(
    queries.map((p_query) =>
      supabase.rpc("search_barcode_products", {
        p_query,
        // Deliberately wide — different chains often carry different SKUs of
        // "the same" product, so a shallow candidate pool can leave a chain
        // with no price at all even though a fine substitute ranks much
        // further down. A generic category query (e.g. "תחליב רחצה") can have
        // dozens of same-similarity-score variants (scent, size) ahead of the
        // one a given chain happens to price — verified one such case ranked
        // #82 among 136 real (non-junk) matches, since the underlying %/<%
        // filter already excludes anything that isn't a genuine match.
        p_limit: 150,
      })
    )
  );

  const seenBarcodes = new Set<string>();
  const candidates: BarcodeProduct[] = [];
  for (const { data } of results) {
    for (const product of data ?? []) {
      if (!seenBarcodes.has(product.barcode)) {
        seenBarcodes.add(product.barcode);
        candidates.push(product);
      }
    }
  }
  if (candidates.length > 0) return { kind: "fuzzy", candidates };
  return { kind: "none" };
}

import { createClient } from "@/lib/supabase/client";
import { stripShoppingFillerWords } from "@/lib/nlp/strip-shopping-filler";
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

  const { data } = await supabase.rpc("search_barcode_products", {
    p_query: stripShoppingFillerWords(item.title),
    // Deliberately wide — different chains often carry different SKUs of
    // "the same" product, so a shallow candidate pool can leave a chain
    // with no price at all even though a fine substitute ranks just a
    // little further down (verified: a generic Nutella jar priced at every
    // chain ranked #11 for a bare "נוטלה" query).
    p_limit: 20,
  });
  if (data && data.length > 0) return { kind: "fuzzy", candidates: data };
  return { kind: "none" };
}

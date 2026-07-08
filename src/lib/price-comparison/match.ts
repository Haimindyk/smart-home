import { createClient } from "@/lib/supabase/client";
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

export type MatchedProduct = {
  product: BarcodeProduct;
  matchType: "exact" | "similar";
  /** Only present for fuzzy matches — omitted (not meaningful) for exact ones. */
  similarity?: number;
};

/**
 * Finds the best barcode_products row for one shopping-list item: an exact
 * barcode lookup first (if the item was scanned), then a trigram
 * title-similarity search as a stand-in for "same brand/size/category" —
 * matching on those individually isn't possible without per-item structured
 * attributes, which our imported chain data doesn't carry.
 */
export async function matchBasketItem(item: BasketInput): Promise<MatchedProduct | null> {
  const supabase = createClient();
  const barcode = extractBarcode(item.notes);

  if (barcode) {
    const { data } = await supabase.from("barcode_products").select("*").eq("barcode", barcode).maybeSingle();
    if (data) return { product: data, matchType: "exact" };
  }

  const { data } = await supabase.rpc("search_barcode_products", { p_query: item.title, p_limit: 1 });
  if (data && data.length > 0) {
    return { product: data[0], matchType: "similar" };
  }
  return null;
}

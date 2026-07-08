import type { ChainKey } from "./chains";

/** The minimal shape a comparison needs from a shopping-list item — callers
 * pass whatever they have (a Task, or anything else with a title). */
export type BasketInput = {
  id: string;
  title: string;
  /** Free-text notes; scanned items carry their barcode in here. */
  notes?: string | null;
};

export type ItemMatch =
  | { status: "exact"; barcode: string; productName: string; price: number }
  | { status: "similar"; barcode: string; productName: string; price: number; similarity: number }
  | { status: "not_found" };

export type BasketItemResult = {
  itemId: string;
  itemTitle: string;
  match: ItemMatch;
};

export type ChainBasketResult = {
  chain: ChainKey;
  chainName: string;
  color: string;
  initial: string;
  /** null when nothing in the basket was found at this chain. */
  total: number | null;
  itemResults: BasketItemResult[];
  matchedCount: number;
  totalCount: number;
};

export type BasketComparison = {
  /** Chains with at least one matched item, cheapest first. */
  ranked: ChainBasketResult[];
  /** Chains where nothing in the basket could be found at all. */
  unavailable: ChainBasketResult[];
  cheapest: ChainBasketResult | null;
  mostExpensive: ChainBasketResult | null;
  savingsAmount: number | null;
  savingsPercent: number | null;
};

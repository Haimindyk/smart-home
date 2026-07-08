import { CHAINS } from "./chains";
import { matchBasketItem, type MatchResult } from "./match";
import type { BarcodeProduct } from "@/types/domain";
import type { BasketComparison, BasketInput, BasketItemResult, ChainBasketResult, ItemMatch } from "./types";
import type { ChainKey, ChainMeta } from "./chains";

/** Picks which candidate row a given chain should price this item from. An
 * exact barcode match is the literal product — used as-is (null price just
 * means that chain doesn't carry that exact barcode). A fuzzy match tries
 * each ranked candidate in order and uses the first one this chain actually
 * has a price for, since different chains often carry different SKUs of
 * "the same" product (a generic jar vs. a single-serve snack pack, say). */
function pickForChain(matched: MatchResult, chain: ChainMeta): BarcodeProduct | null {
  if (matched.kind === "exact") return matched.product;
  if (matched.kind === "fuzzy") {
    return matched.candidates.find((c) => c[chain.priceColumn] != null) ?? null;
  }
  return null;
}

const cache = new Map<string, Promise<BasketComparison>>();

function cacheKey(items: BasketInput[], excludeChains: ChainKey[]): string {
  const itemsKey = items
    .map((i) => `${i.id}:${i.title}:${i.notes ?? ""}`)
    .sort()
    .join("|");
  return `${itemsKey}::${[...excludeChains].sort().join(",")}`;
}

/** Clears cached comparisons — call after an item is added/edited/removed so
 * the next open recomputes instead of showing a stale basket. */
export function clearBasketComparisonCache() {
  cache.clear();
}

async function computeComparison(items: BasketInput[], excludeChains: ChainKey[]): Promise<BasketComparison> {
  const matches = await Promise.all(
    items.map(async (item) => ({ item, matched: await matchBasketItem(item) }))
  );

  const chains = CHAINS.filter((chain) => !excludeChains.includes(chain.key));

  const chainResults: ChainBasketResult[] = chains.map((chain) => {
    let total = 0;
    let matchedCount = 0;

    const itemResults: BasketItemResult[] = matches.map(({ item, matched }) => {
      const product = pickForChain(matched, chain);
      const price = product ? product[chain.priceColumn] : null;
      let match: ItemMatch;
      if (product && price != null) {
        total += price;
        matchedCount += 1;
        match = {
          status: matched.kind === "exact" ? "exact" : "similar",
          barcode: product.barcode,
          productName: product.product_name,
          price,
        };
      } else {
        match = { status: "not_found" };
      }
      return { itemId: item.id, itemTitle: item.title, match };
    });

    return {
      chain: chain.key,
      chainName: chain.name,
      color: chain.color,
      initial: chain.initial,
      total: matchedCount > 0 ? Math.round(total * 100) / 100 : null,
      itemResults,
      matchedCount,
      totalCount: items.length,
    };
  });

  // A chain missing some items only summed the ones it does carry, so its
  // total isn't comparable to a chain pricing the whole basket — ranking
  // purely by total let an incomplete chain "win" cheapest just by being
  // missing (often pricier) items, not by actually costing less. Fully-priced
  // chains are ranked first (by total), with any partial-coverage chains
  // listed after — still shown, but never eligible for the cheapest/most
  // expensive comparison itself.
  const matchedChains = chainResults.filter((c) => c.total != null);
  const fullyMatched = matchedChains.filter((c) => c.matchedCount === c.totalCount).sort((a, b) => a.total! - b.total!);
  const partiallyMatched = matchedChains.filter((c) => c.matchedCount < c.totalCount).sort((a, b) => a.total! - b.total!);
  const ranked = [...fullyMatched, ...partiallyMatched];
  const unavailable = chainResults.filter((c) => c.total == null);

  const cheapest = fullyMatched[0] ?? null;
  const mostExpensive = fullyMatched.length > 0 ? fullyMatched[fullyMatched.length - 1] : null;
  const savingsAmount =
    cheapest && mostExpensive && mostExpensive.total! > cheapest.total!
      ? Math.round((mostExpensive.total! - cheapest.total!) * 100) / 100
      : cheapest && mostExpensive
        ? 0
        : null;
  const savingsPercent =
    savingsAmount != null && mostExpensive && mostExpensive.total! > 0
      ? Math.round((savingsAmount / mostExpensive.total!) * 1000) / 10
      : null;

  return { ranked, unavailable, cheapest, mostExpensive, savingsAmount, savingsPercent };
}

/** Compares a shopping basket across every known chain (minus any the caller
 * excludes — see excludedChainsForSection). Cached per exact basket contents
 * (item id/title/notes) and exclusion set for the life of the session, since
 * recomputing is a handful of network round-trips per open. */
export function compareBasketPrices(items: BasketInput[], excludeChains: ChainKey[] = []): Promise<BasketComparison> {
  const key = cacheKey(items, excludeChains);
  let pending = cache.get(key);
  if (!pending) {
    pending = computeComparison(items, excludeChains);
    cache.set(key, pending);
    pending.catch(() => cache.delete(key));
  }
  return pending;
}

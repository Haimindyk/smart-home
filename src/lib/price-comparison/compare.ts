import { CHAINS } from "./chains";
import { matchBasketItem } from "./match";
import type { BasketComparison, BasketInput, BasketItemResult, ChainBasketResult, ItemMatch } from "./types";

const cache = new Map<string, Promise<BasketComparison>>();

function cacheKey(items: BasketInput[]): string {
  return items
    .map((i) => `${i.id}:${i.title}:${i.notes ?? ""}`)
    .sort()
    .join("|");
}

/** Clears cached comparisons — call after an item is added/edited/removed so
 * the next open recomputes instead of showing a stale basket. */
export function clearBasketComparisonCache() {
  cache.clear();
}

async function computeComparison(items: BasketInput[]): Promise<BasketComparison> {
  const matches = await Promise.all(
    items.map(async (item) => ({ item, matched: await matchBasketItem(item) }))
  );

  const chainResults: ChainBasketResult[] = CHAINS.map((chain) => {
    let total = 0;
    let matchedCount = 0;

    const itemResults: BasketItemResult[] = matches.map(({ item, matched }) => {
      const price = matched ? matched.product[chain.priceColumn] : null;
      let match: ItemMatch;
      if (matched && price != null) {
        total += price;
        matchedCount += 1;
        match =
          matched.matchType === "exact"
            ? { status: "exact", barcode: matched.product.barcode, productName: matched.product.product_name, price }
            : {
                status: "similar",
                barcode: matched.product.barcode,
                productName: matched.product.product_name,
                price,
                similarity: matched.similarity ?? 0,
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

  const ranked = chainResults.filter((c) => c.total != null).sort((a, b) => a.total! - b.total!);
  const unavailable = chainResults.filter((c) => c.total == null);

  const cheapest = ranked[0] ?? null;
  const mostExpensive = ranked.length > 0 ? ranked[ranked.length - 1] : null;
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

/** Compares a shopping basket across every known chain. Cached per exact
 * basket contents (item id/title/notes) for the life of the session, since
 * recomputing is a handful of network round-trips per open. */
export function compareBasketPrices(items: BasketInput[]): Promise<BasketComparison> {
  const key = cacheKey(items);
  let pending = cache.get(key);
  if (!pending) {
    pending = computeComparison(items);
    cache.set(key, pending);
    pending.catch(() => cache.delete(key));
  }
  return pending;
}

"use client";

import { useEffect, useState } from "react";
import { ChevronDown, ChevronRight, Loader2 } from "lucide-react";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from "@/components/ui/sheet";
import { Badge } from "@/components/ui/badge";
import { useT } from "@/lib/i18n/store";
import { compareBasketPrices } from "@/lib/price-comparison/compare";
import type { ChainKey } from "@/lib/price-comparison/chains";
import type { BasketComparison, BasketInput, ChainBasketResult } from "@/lib/price-comparison/types";
import { cn } from "@/lib/utils";

/**
 * Reusable anywhere a "compare this basket across chains" experience is
 * needed — takes only a plain list of {id, title, notes}, so it isn't tied
 * to shopping sections specifically.
 */
export function PriceComparisonSheet({
  items,
  excludeChains = [],
  open,
  onOpenChange,
}: {
  items: BasketInput[];
  /** Chains to leave out of this comparison — see excludedChainsForSection. */
  excludeChains?: ChainKey[];
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const t = useT();
  const [comparison, setComparison] = useState<BasketComparison | null>(null);
  // Reset to "nothing computed yet" each time the sheet opens — adjusting
  // state during render per
  // https://react.dev/learn/you-might-not-need-an-effect#adjusting-some-state-when-a-prop-changes
  const [syncedOpen, setSyncedOpen] = useState(open);
  if (open !== syncedOpen) {
    setSyncedOpen(open);
    if (open) setComparison(null);
  }
  const loading = items.length > 0 && comparison === null;

  useEffect(() => {
    if (!open || items.length === 0) return;
    let cancelled = false;
    void compareBasketPrices(items, excludeChains).then((result) => {
      if (!cancelled) setComparison(result);
    });
    return () => {
      cancelled = true;
    };
    // `items`/`excludeChains` are array literals built fresh every render by
    // the caller — comparing contents (not identity) is handled inside
    // compareBasketPrices' own cache key, so re-running on every render here
    // is unnecessary; only `open` should retrigger a fetch.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent
        side="bottom"
        className="surface-shadow flex max-h-[85dvh] flex-col gap-0 overflow-hidden rounded-t-3xl p-0 sm:inset-x-auto sm:start-1/2 sm:bottom-8 sm:w-full sm:max-w-lg sm:-translate-x-1/2 sm:rounded-3xl rtl:sm:translate-x-1/2"
      >
        <SheetHeader className="border-b border-border/60 px-5 py-4">
          <SheetTitle className="text-lg">{t("priceComparison")}</SheetTitle>
          <SheetDescription>{t("priceComparisonSubtitle")}</SheetDescription>
        </SheetHeader>

        <div className="flex-1 overflow-y-auto px-4 py-4">
          {items.length === 0 ? (
            <p className="py-10 text-center text-sm text-muted-foreground">{t("basketEmptyForComparison")}</p>
          ) : loading || !comparison ? (
            <div className="flex flex-col items-center gap-3 py-10 text-sm text-muted-foreground">
              <Loader2 className="size-5 animate-spin" />
              {t("comparingPrices")}
            </div>
          ) : comparison.ranked.length === 0 ? (
            <p className="py-10 text-center text-sm text-muted-foreground">{t("noChainsAvailable")}</p>
          ) : (
            <div className="flex flex-col gap-3">
              {comparison.ranked.map((chain, i) => (
                <ChainCard
                  key={chain.chain}
                  chain={chain}
                  isCheapest={i === 0}
                  mostExpensiveTotal={comparison.mostExpensive?.total ?? null}
                />
              ))}
              {comparison.unavailable.length > 0 && (
                <p className="pt-1 text-center text-xs text-muted-foreground">
                  {t("chainsWithNoMatch")}: {comparison.unavailable.map((c) => c.chainName).join(", ")}
                </p>
              )}
            </div>
          )}
        </div>
      </SheetContent>
    </Sheet>
  );
}

function ChainCard({
  chain,
  isCheapest,
  mostExpensiveTotal,
}: {
  chain: ChainBasketResult;
  isCheapest: boolean;
  mostExpensiveTotal: number | null;
}) {
  const t = useT();
  const [expanded, setExpanded] = useState(false);
  const savings = mostExpensiveTotal != null && chain.total != null ? mostExpensiveTotal - chain.total : null;
  const savingsPercent =
    savings != null && mostExpensiveTotal ? Math.round((savings / mostExpensiveTotal) * 1000) / 10 : null;

  return (
    <div
      className={cn(
        "surface-shadow overflow-hidden rounded-2xl ring-1 transition-colors",
        isCheapest ? "bg-primary/5 ring-2 ring-primary/60" : "bg-card/60 ring-border/40"
      )}
    >
      <div className="flex items-center gap-3 p-4">
        <div
          className={cn(
            "flex size-11 shrink-0 items-center justify-center rounded-2xl text-lg font-bold text-white shadow-[inset_0_1px_1px_rgba(255,255,255,0.25)]",
            chain.color
          )}
        >
          {chain.initial}
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-1.5">
            <span className="font-semibold" dir="auto">
              {chain.chainName}
            </span>
            {isCheapest && (
              <Badge className="h-5 gap-1 border-0 bg-emerald-600 text-white">🟢 {t("cheapestBasket")}</Badge>
            )}
          </div>
          <p className="text-xs text-muted-foreground">
            {t("itemsFoundCount")
              .replace("{matched}", String(chain.matchedCount))
              .replace("{total}", String(chain.totalCount))}
          </p>
        </div>
        <div className="shrink-0 text-end">
          <p className="text-lg font-bold tabular-nums">₪{chain.total!.toFixed(2)}</p>
          {!isCheapest && savings != null && savings > 0 && (
            <p className="text-xs font-medium text-emerald-600 dark:text-emerald-400">
              💰 ₪{savings.toFixed(2)} ({savingsPercent}%)
            </p>
          )}
        </div>
      </div>

      <button
        type="button"
        onClick={() => setExpanded((v) => !v)}
        className="flex w-full items-center justify-center gap-1 border-t border-border/40 py-2 text-xs font-medium text-muted-foreground transition-colors hover:bg-accent/40"
      >
        {expanded ? (
          <ChevronDown className="size-3.5" />
        ) : (
          <ChevronRight className="size-3.5 rtl:rotate-180" />
        )}
        {expanded ? t("hideItems") : t("showItems")}
      </button>

      {expanded && (
        <div className="flex flex-col gap-1.5 border-t border-border/40 bg-muted/30 p-3">
          {chain.itemResults.map((item) => (
            <div key={item.itemId} className="flex items-center justify-between gap-2 text-xs">
              <div className="min-w-0 flex-1">
                <p className="truncate font-medium" dir="auto">
                  {item.itemTitle}
                </p>
                {item.match.status !== "not_found" && item.match.productName !== item.itemTitle && (
                  <p className="truncate text-muted-foreground" dir="auto">
                    {item.match.productName}
                  </p>
                )}
              </div>
              {item.match.status === "not_found" ? (
                <span className="shrink-0 text-muted-foreground">{t("noSuitableProduct")}</span>
              ) : (
                <div className="flex shrink-0 items-center gap-1.5">
                  <Badge
                    variant={item.match.status === "exact" ? "secondary" : "outline"}
                    className="h-5 text-[10px]"
                  >
                    {item.match.status === "exact" ? t("exactMatch") : t("similarProduct")}
                  </Badge>
                  <span className="font-medium tabular-nums">₪{item.match.price.toFixed(2)}</span>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

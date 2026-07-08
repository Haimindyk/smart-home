"use client";

import { useState } from "react";
import { TrendingDown } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useT } from "@/lib/i18n/store";
import { PriceComparisonSheet } from "@/components/shopping/price-comparison-sheet";
import type { BasketInput } from "@/lib/price-comparison/types";

/** Drop into any section header (or anywhere else a basket needs comparing)
 * to open the price-comparison sheet for that list of items. */
export function PriceComparisonButton({ items }: { items: BasketInput[] }) {
  const t = useT();
  const [open, setOpen] = useState(false);

  return (
    <>
      <Button
        variant="outline"
        size="sm"
        className="h-8 w-full gap-1.5 rounded-full border-primary/30 bg-primary/10 font-semibold text-primary hover:bg-primary/20 hover:text-primary sm:w-auto"
        onClick={() => setOpen(true)}
      >
        <TrendingDown className="size-4" />
        {t("priceComparison")}
      </Button>
      <PriceComparisonSheet items={items} open={open} onOpenChange={setOpen} />
    </>
  );
}

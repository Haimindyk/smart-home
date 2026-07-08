"use client";

import { useState } from "react";
import { Plus, ScanBarcode, Search, StickyNote } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import { parseQuickAdd } from "@/lib/nlp/quick-add-parse";
import { useProductSearch } from "@/lib/hooks/use-product-search";
import { BarcodeScannerDialog } from "@/components/shopping/barcode-scanner-dialog";
import { cn } from "@/lib/utils";
import type { SectionKind } from "@/types/domain";

export function QuickAddInput({
  sectionId,
  sectionKind,
  createdBy,
}: {
  sectionId: string;
  sectionKind: SectionKind;
  createdBy: string | null;
}) {
  const createTask = useAppStore((s) => s.createTask);
  const t = useT();
  const [value, setValue] = useState("");
  const [asNote, setAsNote] = useState(false);
  const [scannerOpen, setScannerOpen] = useState(false);
  const [selectedBarcode, setSelectedBarcode] = useState<string | null>(null);
  const [suggestionsOpen, setSuggestionsOpen] = useState(false);
  const isInfoSection = sectionKind === "info";
  const isShoppingSection = sectionKind === "shopping";

  const suggestions = useProductSearch(value, isShoppingSection && !asNote && suggestionsOpen);

  function submit() {
    if (!value.trim()) return;
    if (asNote || isInfoSection) {
      void createTask({
        sectionId,
        title: value.trim(),
        createdBy,
        extra: { is_note: true },
      });
    } else {
      const { title, dueAt } = parseQuickAdd(value);
      void createTask({
        sectionId,
        title,
        createdBy,
        extra: {
          ...(dueAt ? { due_at: dueAt } : {}),
          ...(selectedBarcode ? { notes: `${t("scannedBarcode")}: ${selectedBarcode}` } : {}),
        },
      });
    }
    setValue("");
    setAsNote(false);
    setSelectedBarcode(null);
    setSuggestionsOpen(false);
  }

  function pickSuggestion(productName: string, barcode: string) {
    setValue(productName);
    setSelectedBarcode(barcode);
    setSuggestionsOpen(false);
  }

  return (
    <div className="relative mb-3">
      <form
        className="glass flex items-center gap-2 rounded-2xl px-3 py-2.5 ring-1 ring-border/40 transition-shadow duration-150 ease-(--ease-premium) focus-within:shadow-md focus-within:ring-ring/50"
        onSubmit={(e) => {
          e.preventDefault();
          submit();
        }}
      >
        {isInfoSection ? (
          <StickyNote className="size-4 shrink-0 text-muted-foreground" />
        ) : (
          <button
            type="button"
            onClick={() => setAsNote((v) => !v)}
            aria-pressed={asNote}
            title={t("addAsNote")}
            className={cn(
              "flex shrink-0 items-center gap-1 rounded-lg px-1.5 py-1 text-xs font-medium transition-colors",
              asNote
                ? "bg-primary text-primary-foreground"
                : "text-muted-foreground hover:bg-accent",
            )}
          >
            {asNote ? <StickyNote className="size-4" /> : <Plus className="size-4" />}
            <span className="hidden sm:inline">{t("addAsNote")}</span>
          </button>
        )}
        <input
          dir="auto"
          value={value}
          onChange={(e) => {
            setValue(e.target.value);
            if (selectedBarcode) setSelectedBarcode(null);
          }}
          onFocus={() => setSuggestionsOpen(true)}
          onBlur={() => setSuggestionsOpen(false)}
          placeholder={
            isInfoSection || asNote
              ? t("addNotePlaceholder")
              : sectionKind === "chores"
                ? t("addChore")
                : t("quickAddPlaceholder")
          }
          className="w-full bg-transparent text-sm outline-none"
        />
        {isShoppingSection && (
          <button
            type="button"
            onClick={() => setScannerOpen(true)}
            title={t("scanBarcode")}
            aria-label={t("scanBarcode")}
            className="flex shrink-0 items-center justify-center rounded-lg p-1.5 text-muted-foreground transition-colors hover:bg-accent"
          >
            <ScanBarcode className="size-4" />
          </button>
        )}
        {isShoppingSection && (
          <BarcodeScannerDialog
            open={scannerOpen}
            onOpenChange={setScannerOpen}
            sectionId={sectionId}
            createdBy={createdBy}
          />
        )}
      </form>

      {suggestions.length > 0 && (
        <div className="surface-shadow absolute inset-x-0 top-[calc(100%+4px)] z-20 overflow-hidden rounded-2xl bg-popover ring-1 ring-border/60">
          {suggestions.map((product) => (
            <button
              key={product.barcode}
              type="button"
              // mousedown (not click) fires before the input's blur, so the
              // selection is applied instead of the dropdown just closing.
              onMouseDown={(e) => {
                e.preventDefault();
                pickSuggestion(product.product_name, product.barcode);
              }}
              className="flex w-full items-center gap-2 px-3 py-2 text-start text-sm transition-colors hover:bg-accent/60"
            >
              <Search className="size-3.5 shrink-0 text-muted-foreground" />
              <span dir="auto" className="truncate">
                {product.product_name}
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

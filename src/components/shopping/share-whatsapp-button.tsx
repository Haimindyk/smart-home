"use client";

import { MessageCircle } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { useT } from "@/lib/i18n/store";

type ShareItem = { title: string; notes?: string | null };

/** Drop into a shopping section's header to send its pending items to WhatsApp
 * as a plain-text list, via the wa.me share link. */
export function ShareWhatsappButton({ sectionName, items }: { sectionName: string; items: ShareItem[] }) {
  const t = useT();

  function share() {
    if (items.length === 0) {
      toast.info(t("shoppingListEmptyForShare"));
      return;
    }
    const header = t("shoppingListShareHeader").replace("{section}", sectionName);
    const lines = items.map((item) => `• ${item.title}${item.notes ? ` (${item.notes})` : ""}`);
    const text = [header, ...lines].join("\n");
    window.open(`https://wa.me/?text=${encodeURIComponent(text)}`, "_blank", "noopener,noreferrer");
  }

  return (
    <Button
      variant="outline"
      size="sm"
      className="h-8 w-full gap-1.5 rounded-full border-emerald-500/30 bg-emerald-500/10 font-semibold text-emerald-600 hover:bg-emerald-500/20 hover:text-emerald-600 dark:text-emerald-400 sm:w-auto"
      onClick={share}
    >
      <MessageCircle className="size-4" />
      {t("shareShoppingList")}
    </Button>
  );
}

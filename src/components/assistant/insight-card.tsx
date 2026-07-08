"use client";

import { useState } from "react";
import { X } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import { applyProposedAction } from "@/lib/assistant/apply-actions";
import type { ProposedAction } from "@/lib/assistant/types";
import { Button } from "@/components/ui/button";
import { toast } from "sonner";

/** Dismissible dashboard cards for the periodic insights sweep (see
 * supabase/functions/assistant's "insights" mode + migration 0022's
 * ai_suggestions table). Renders nothing once there are no open ones. */
export function InsightCards() {
  const aiSuggestions = useAppStore((s) => s.aiSuggestions);
  const updateAiSuggestionStatus = useAppStore((s) => s.updateAiSuggestionStatus);
  const t = useT();
  const [applyingId, setApplyingId] = useState<string | null>(null);

  const open = Object.values(aiSuggestions)
    .filter((s) => s.status === "open")
    .sort((a, b) => (a.created_at < b.created_at ? 1 : -1));

  if (open.length === 0) return null;

  async function apply(id: string, action: ProposedAction) {
    setApplyingId(id);
    try {
      await applyProposedAction(action);
      await updateAiSuggestionStatus(id, "applied");
    } catch {
      toast.error(t("assistantActionFailed"));
    }
    setApplyingId(null);
  }

  return (
    <div className="mb-4 flex flex-col gap-2">
      {open.map((s) => (
        <div key={s.id} className="glass surface-shadow flex items-center gap-3 rounded-2xl p-3.5 ring-1 ring-primary/30">
          <span className="text-xl">{s.emoji ?? "💡"}</span>
          <p dir="auto" className="flex-1 text-sm">
            {s.summary}
          </p>
          <Button
            size="sm"
            disabled={applyingId === s.id}
            onClick={() => void apply(s.id, s.action as unknown as ProposedAction)}
          >
            {t("add")}
          </Button>
          <Button
            variant="ghost"
            size="icon"
            className="size-7"
            onClick={() => void updateAiSuggestionStatus(s.id, "dismissed")}
            aria-label={t("dismiss")}
          >
            <X className="size-4" />
          </Button>
        </div>
      ))}
    </div>
  );
}

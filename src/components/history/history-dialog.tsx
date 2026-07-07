"use client";

import { formatDistanceToNow } from "date-fns";
import { he, enUS } from "date-fns/locale";
import { History as HistoryIcon } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useLocaleStore, useT } from "@/lib/i18n/store";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import type { MessageKey } from "@/lib/i18n/messages";

const ACTION_KEYS: Record<string, MessageKey> = {
  created: "action_created",
  updated: "action_updated",
  renamed: "action_renamed",
  completed: "action_completed",
  uncompleted: "action_uncompleted",
  deleted: "action_deleted",
  restored: "action_restored",
};

export function HistoryDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  const activityLog = useAppStore((s) => s.activityLog);
  const members = useAppStore((s) => s.members);
  const locale = useLocaleStore((s) => s.locale);
  const t = useT();

  const entries = Object.values(activityLog).sort((a, b) => (a.created_at < b.created_at ? 1 : -1));

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[80vh] overflow-y-auto sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <HistoryIcon className="size-4" /> {t("history")}
          </DialogTitle>
        </DialogHeader>

        {entries.length === 0 ? (
          <p className="py-6 text-center text-sm text-muted-foreground">{t("noHistoryYet")}</p>
        ) : (
          <ul className="flex flex-col gap-1">
            {entries.map((entry) => {
              const actor = entry.actor_id ? members[entry.actor_id] : undefined;
              const actionKey = ACTION_KEYS[entry.action] ?? "action_updated";
              return (
                <li key={entry.id} className="flex items-start gap-2.5 rounded-lg px-2 py-2 hover:bg-accent/50">
                  <span className="text-lg leading-none">{actor?.avatar_emoji ?? "❔"}</span>
                  <div className="flex min-w-0 flex-col">
                    <p className="text-sm">
                      <span className="font-medium" style={actor ? { color: actor.color } : undefined}>
                        {actor?.display_name ?? t("guest")}
                      </span>{" "}
                      <span className="text-muted-foreground">{t(actionKey)}</span>{" "}
                      <span dir="auto" className="font-medium">
                        {entry.summary ?? ""}
                      </span>
                    </p>
                    <span className="text-xs text-muted-foreground">
                      {formatDistanceToNow(new Date(entry.created_at), {
                        addSuffix: true,
                        locale: locale === "he" ? he : enUS,
                      })}
                    </span>
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </DialogContent>
    </Dialog>
  );
}

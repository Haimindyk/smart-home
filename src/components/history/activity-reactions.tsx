"use client";

import { useMemo } from "react";
import { SmilePlus } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useIdentity } from "@/lib/identity";
import { useT } from "@/lib/i18n/store";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { cn } from "@/lib/utils";

/** Small, fixed palette so reactions stay a quick tap, not a full emoji picker. */
const QUICK_EMOJIS = ["👍", "❤️", "😂", "👀", "✅"];

/** A row of emoji reaction pills for one activity_log entry — tap an emoji to
 * add/remove your own reaction, see who else already reacted via the count. */
export function ActivityReactions({ entryId }: { entryId: string }) {
  const reactions = useAppStore((s) => s.activityLogReactions);
  const members = useAppStore((s) => s.members);
  const toggleReaction = useAppStore((s) => s.toggleReaction);
  const actingMemberId = useIdentity((s) => s.actingMemberId);
  const t = useT();

  const groups = useMemo(() => {
    const byEmoji = new Map<string, { count: number; mine: boolean; names: string[] }>();
    for (const r of Object.values(reactions)) {
      if (r.activity_log_id !== entryId) continue;
      const entry = byEmoji.get(r.emoji) ?? { count: 0, mine: false, names: [] };
      entry.count++;
      if (r.member_id === actingMemberId) entry.mine = true;
      entry.names.push(members[r.member_id]?.display_name ?? "");
      byEmoji.set(r.emoji, entry);
    }
    return byEmoji;
  }, [reactions, entryId, actingMemberId, members]);

  const handleToggle = (emoji: string) => {
    if (!actingMemberId) return;
    void toggleReaction(entryId, actingMemberId, emoji);
  };

  return (
    <div className="flex items-center gap-1">
      {[...groups.entries()].map(([emoji, { count, mine, names }]) => (
        <button
          key={emoji}
          type="button"
          title={names.filter(Boolean).join(", ")}
          onClick={() => handleToggle(emoji)}
          disabled={!actingMemberId}
          className={cn(
            "flex items-center gap-0.5 rounded-full border px-1.5 py-0.5 text-xs leading-none transition-colors",
            mine ? "border-primary/40 bg-primary/10" : "border-transparent bg-accent/50 hover:bg-accent"
          )}
        >
          <span>{emoji}</span>
          <span className="text-muted-foreground">{count}</span>
        </button>
      ))}

      {actingMemberId && (
        <Popover>
          <PopoverTrigger
            title={t("addReaction")}
            className="flex size-5 items-center justify-center rounded-full text-muted-foreground hover:bg-accent"
          >
            <SmilePlus className="size-3.5" />
          </PopoverTrigger>
          <PopoverContent className="w-auto p-1">
            <div className="flex gap-0.5">
              {QUICK_EMOJIS.map((emoji) => (
                <button
                  key={emoji}
                  type="button"
                  onClick={() => handleToggle(emoji)}
                  className={cn(
                    "flex size-8 items-center justify-center rounded-md text-lg hover:bg-accent",
                    groups.get(emoji)?.mine && "bg-primary/10"
                  )}
                >
                  {emoji}
                </button>
              ))}
            </div>
          </PopoverContent>
        </Popover>
      )}
    </div>
  );
}

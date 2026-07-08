"use client";

import { useMemo, useState } from "react";
import { Check, History } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useIdentity } from "@/lib/identity";
import { useT } from "@/lib/i18n/store";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { AssigneeBadge } from "@/components/tasks/assignee-badge";
import { ChoreEditorSheet } from "@/components/chores/chore-editor-sheet";
import { cn } from "@/lib/utils";
import type { Chore } from "@/types/domain";

export function ChoreRow({ chore }: { chore: Chore }) {
  const completeChore = useAppStore((s) => s.completeChore);
  const choreCompletions = useAppStore((s) => s.choreCompletions);
  const members = useAppStore((s) => s.members);
  const actingMemberId = useIdentity((s) => s.actingMemberId);
  const t = useT();
  const [editing, setEditing] = useState(false);

  const isDue = new Date(chore.next_due_at).getTime() <= Date.now();

  const history = useMemo(
    () =>
      Object.values(choreCompletions)
        .filter((c) => c.chore_id === chore.id)
        .sort((a, b) => (a.completed_at > b.completed_at ? -1 : 1))
        .slice(0, 10),
    [choreCompletions, chore.id]
  );

  return (
    <div className="glass flex items-center gap-2.5 rounded-2xl px-3.5 py-3 ring-1 ring-border/40 transition-shadow duration-150 ease-(--ease-premium) hover:shadow-md">
      <Button
        size="icon"
        variant={isDue ? "default" : "outline"}
        className={cn("size-9 shrink-0 rounded-full", isDue && "bg-gradient-to-br from-indigo-500 to-violet-600")}
        disabled={!actingMemberId}
        title={actingMemberId ? t("markDone") : t("whoAreYou")}
        onClick={() => actingMemberId && completeChore(chore.id, actingMemberId)}
      >
        <Check className="size-4" />
      </Button>

      <button
        type="button"
        className="flex flex-1 flex-col gap-0.5 text-start"
        onClick={() => setEditing(true)}
      >
        <div className="flex items-center gap-2">
          {chore.emoji && <span>{chore.emoji}</span>}
          <span dir="auto" className={cn("text-sm font-medium", !isDue && "text-muted-foreground")}>
            {chore.title}
          </span>
        </div>
        <div className="flex items-center gap-1.5">
          <Badge variant="secondary" className="h-5 text-[11px]">
            {t(chore.freq)}
          </Badge>
          {!isDue && (
            <span className="text-[11px] text-muted-foreground">
              {new Date(chore.next_due_at).toLocaleDateString("he-IL")}
            </span>
          )}
        </div>
      </button>

      <AssigneeBadge
        assigneeKind={chore.assignee_kind}
        assigneeMemberId={chore.assignee_member_id}
        assigneeMemberIds={chore.assignee_member_ids}
      />

      <Popover>
        <PopoverTrigger render={<Button variant="ghost" size="icon" className="size-7" />}>
          <History className="size-3.5" />
        </PopoverTrigger>
        <PopoverContent align="end" className="w-64">
          <p className="mb-2 text-xs font-medium text-muted-foreground">{t("history")}</p>
          {history.length === 0 && <p className="text-xs text-muted-foreground">—</p>}
          <ul className="flex flex-col gap-1.5">
            {history.map((h) => (
              <li key={h.id} className="flex justify-between text-xs">
                <span>{members[h.completed_by]?.display_name ?? "?"}</span>
                <span className="text-muted-foreground">{new Date(h.completed_at).toLocaleDateString("he-IL")}</span>
              </li>
            ))}
          </ul>
        </PopoverContent>
      </Popover>

      <ChoreEditorSheet choreId={editing ? chore.id : null} onOpenChange={setEditing} />
    </div>
  );
}

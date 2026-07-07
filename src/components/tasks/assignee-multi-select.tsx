"use client";

import { useState } from "react";
import { Check, ChevronDown } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import type { AssigneeKind } from "@/types/domain";

export type AssigneeSelection = {
  assignee_kind: AssigneeKind;
  assignee_member_ids: string[];
};

/**
 * Reusable assignee picker for both tasks and chores. "Anyone" / "Louis" /
 * "Unassigned" are mutually exclusive alternatives to picking one-or-more
 * specific members — the array (`assignee_member_ids`) is the source of
 * truth for "assigned to specific member(s)"; `assignee_kind === "member"`
 * just means that array is non-empty.
 */
export function AssigneeMultiSelect({
  assigneeKind,
  assigneeMemberIds,
  onChange,
  allowUnassigned = true,
}: {
  assigneeKind: AssigneeKind;
  assigneeMemberIds: string[];
  onChange: (next: AssigneeSelection) => void;
  /** Tasks allow "unassigned"; chores don't (see ChoreAssigneeKind). */
  allowUnassigned?: boolean;
}) {
  const members = useAppStore((s) => s.members);
  const t = useT();
  const [open, setOpen] = useState(false);

  const memberList = Object.values(members);
  const fallbackKind: AssigneeKind = allowUnassigned ? "unassigned" : "anyone";

  function selectSpecial(kind: "unassigned" | "anyone" | "louis") {
    onChange({ assignee_kind: kind, assignee_member_ids: [] });
    setOpen(false);
  }

  function toggleMember(id: string) {
    const next = assigneeMemberIds.includes(id)
      ? assigneeMemberIds.filter((m) => m !== id)
      : [...assigneeMemberIds, id];
    onChange({
      assignee_kind: next.length > 0 ? "member" : fallbackKind,
      assignee_member_ids: next,
    });
  }

  const label = (() => {
    if (assigneeKind === "member" && assigneeMemberIds.length > 0) {
      if (assigneeMemberIds.length === 1) {
        const m = members[assigneeMemberIds[0]];
        return m ? `${m.avatar_emoji} ${m.display_name}` : t("assignees");
      }
      const first = members[assigneeMemberIds[0]];
      return `${first ? first.avatar_emoji : ""} +${assigneeMemberIds.length - 1}`.trim();
    }
    if (assigneeKind === "anyone") return t("anyone");
    if (assigneeKind === "louis") return t("louis");
    return t("unassigned");
  })();

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger render={<Button variant="outline" className="justify-between gap-2 font-normal" />}>
        <span className="truncate">{label}</span>
        <ChevronDown className="size-4 shrink-0 opacity-60" />
      </PopoverTrigger>
      <PopoverContent align="start" className="w-64 p-2">
        <div className="flex flex-col gap-0.5">
          {allowUnassigned && (
            <button
              type="button"
              className="flex items-center justify-between rounded-lg px-2 py-1.5 text-start text-sm hover:bg-accent"
              onClick={() => selectSpecial("unassigned")}
            >
              {t("unassigned")}
              {assigneeKind === "unassigned" && <Check className="size-4" />}
            </button>
          )}
          <button
            type="button"
            className="flex items-center justify-between rounded-lg px-2 py-1.5 text-start text-sm hover:bg-accent"
            onClick={() => selectSpecial("anyone")}
          >
            {t("anyone")}
            {assigneeKind === "anyone" && <Check className="size-4" />}
          </button>
          <button
            type="button"
            className="flex items-center justify-between rounded-lg px-2 py-1.5 text-start text-sm hover:bg-accent"
            onClick={() => selectSpecial("louis")}
          >
            {t("louis")}
            {assigneeKind === "louis" && <Check className="size-4" />}
          </button>
        </div>

        <div className="my-2 h-px bg-border" />

        <p className="px-2 pb-1 text-xs font-medium text-muted-foreground">{t("assignees")}</p>
        <div className="flex max-h-48 flex-col gap-0.5 overflow-y-auto">
          {memberList.map((m) => (
            <label
              key={m.id}
              className="flex items-center gap-2 rounded-lg px-2 py-1.5 text-sm hover:bg-accent"
            >
              <Checkbox checked={assigneeMemberIds.includes(m.id)} onCheckedChange={() => toggleMember(m.id)} />
              <span>{m.avatar_emoji}</span>
              <span className="truncate">{m.display_name}</span>
            </label>
          ))}
        </div>
      </PopoverContent>
    </Popover>
  );
}

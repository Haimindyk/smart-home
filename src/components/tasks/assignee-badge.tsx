"use client";

import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import { Badge } from "@/components/ui/badge";
import { MemberAvatar } from "@/components/identity/member-avatar";
import type { AssigneeKind } from "@/types/domain";

export function AssigneeBadge({
  assigneeKind,
  assigneeMemberId,
  assigneeMemberIds,
}: {
  assigneeKind: AssigneeKind;
  /** Legacy single-assignee id — used as a fallback for rows the array backfill somehow missed. */
  assigneeMemberId?: string | null;
  assigneeMemberIds?: string[];
}) {
  const members = useAppStore((s) => s.members);
  const t = useT();

  if (assigneeKind === "unassigned") return null;

  if (assigneeKind === "member") {
    const ids =
      assigneeMemberIds && assigneeMemberIds.length > 0
        ? assigneeMemberIds
        : assigneeMemberId
          ? [assigneeMemberId]
          : [];

    if (ids.length === 0) return null;

    if (ids.length === 1) {
      const member = members[ids[0]];
      if (!member) return null;
      return (
        <Badge
          variant="outline"
          className="h-7 gap-1.5 border-0 ps-0.5"
          style={{ backgroundColor: `${member.color}22`, color: member.color }}
        >
          <MemberAvatar member={member} className="size-6" emojiClassName="text-base" />
          {member.display_name}
        </Badge>
      );
    }

    return (
      <div className="flex items-center -space-x-2 rtl:space-x-reverse">
        {ids.slice(0, 4).map((id) => {
          const member = members[id];
          if (!member) return null;
          return (
            <span
              key={id}
              title={member.display_name}
              className="flex size-7 items-center justify-center overflow-hidden rounded-full text-sm ring-2 ring-background"
              style={{ backgroundColor: `${member.color}33` }}
            >
              <MemberAvatar member={member} className="size-7" emojiClassName="text-base" />
            </span>
          );
        })}
        {ids.length > 4 && (
          <span className="flex size-7 items-center justify-center rounded-full bg-muted text-xs ring-2 ring-background">
            +{ids.length - 4}
          </span>
        )}
      </div>
    );
  }

  if (assigneeKind === "louis") {
    return (
      <Badge variant="outline" className="gap-1">
        {t("louis")}
      </Badge>
    );
  }

  return (
    <Badge variant="outline" className="gap-1">
      {t("anyone")}
    </Badge>
  );
}

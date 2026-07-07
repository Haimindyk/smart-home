"use client";

import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import { Badge } from "@/components/ui/badge";
import type { AssigneeKind } from "@/types/domain";

export function AssigneeBadge({
  assigneeKind,
  assigneeMemberId,
}: {
  assigneeKind: AssigneeKind;
  assigneeMemberId: string | null;
}) {
  const member = useAppStore((s) => (assigneeMemberId ? s.members[assigneeMemberId] : undefined));
  const t = useT();

  if (assigneeKind === "unassigned") return null;

  if (assigneeKind === "member" && member) {
    return (
      <Badge
        variant="outline"
        className="gap-1 border-0"
        style={{ backgroundColor: `${member.color}22`, color: member.color }}
      >
        <span>{member.avatar_emoji}</span>
        {member.display_name}
      </Badge>
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

"use client";

import { useMemo } from "react";
import { useAppStore } from "@/lib/store/app-store";
import type { Section } from "@/types/domain";

export function useSectionStats(section: Section) {
  const tasks = useAppStore((s) => s.tasks);
  const chores = useAppStore((s) => s.chores);

  return useMemo(() => {
    if (section.kind === "chores") {
      const items = Object.values(chores).filter((c) => c.section_id === section.id && !c.deleted_at);
      const now = Date.now();
      const pendingCount = items.filter((c) => new Date(c.next_due_at).getTime() <= now).length;
      const lastEdited = items.reduce<string | null>((acc, c) => (!acc || c.updated_at > acc ? c.updated_at : acc), section.updated_at);
      return { total: items.length, completed: items.length - pendingCount, pending: pendingCount, lastEdited };
    }
    const items = Object.values(tasks).filter((task) => task.section_id === section.id && !task.deleted_at && !task.is_note);
    const completed = items.filter((task) => task.is_completed).length;
    const lastEdited = items.reduce<string | null>((acc, task) => (!acc || task.updated_at > acc ? task.updated_at : acc), section.updated_at);
    return { total: items.length, completed, pending: items.length - completed, lastEdited };
  }, [tasks, chores, section]);
}

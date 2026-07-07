"use client";

import { useState } from "react";
import { Plus } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import { parseQuickAdd } from "@/lib/nlp/quick-add-parse";
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

  function submit() {
    if (!value.trim()) return;
    const { title, dueAt } = parseQuickAdd(value);
    void createTask({
      sectionId,
      title,
      createdBy,
      extra: dueAt ? { due_at: dueAt } : undefined,
    });
    setValue("");
  }

  return (
    <form
      className="mb-2 flex items-center gap-2 rounded-lg border bg-card px-2 py-1.5 shadow-sm"
      onSubmit={(e) => {
        e.preventDefault();
        submit();
      }}
    >
      <Plus className="size-4 shrink-0 text-muted-foreground" />
      <input
        dir="auto"
        value={value}
        onChange={(e) => setValue(e.target.value)}
        placeholder={sectionKind === "chores" ? t("addChore") : t("quickAddPlaceholder")}
        className="w-full bg-transparent text-sm outline-none"
      />
    </form>
  );
}

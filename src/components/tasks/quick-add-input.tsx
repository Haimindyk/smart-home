"use client";

import { useState } from "react";
import { Plus, StickyNote } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import { parseQuickAdd } from "@/lib/nlp/quick-add-parse";
import { cn } from "@/lib/utils";
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
  const [asNote, setAsNote] = useState(false);

  function submit() {
    if (!value.trim()) return;
    if (asNote) {
      void createTask({
        sectionId,
        title: value.trim(),
        createdBy,
        extra: { is_note: true },
      });
    } else {
      const { title, dueAt } = parseQuickAdd(value);
      void createTask({
        sectionId,
        title,
        createdBy,
        extra: dueAt ? { due_at: dueAt } : undefined,
      });
    }
    setValue("");
    setAsNote(false);
  }

  return (
    <form
      className="glass mb-3 flex items-center gap-2 rounded-2xl px-3 py-2.5 ring-1 ring-border/60 transition-shadow focus-within:shadow-md focus-within:ring-ring/50"
      onSubmit={(e) => {
        e.preventDefault();
        submit();
      }}
    >
      <button
        type="button"
        onClick={() => setAsNote((v) => !v)}
        aria-pressed={asNote}
        title={t("addAsNote")}
        className={cn(
          "flex size-6 shrink-0 items-center justify-center rounded-lg transition-colors",
          asNote
            ? "bg-primary text-primary-foreground"
            : "text-muted-foreground hover:bg-accent",
        )}
      >
        {asNote ? (
          <StickyNote className="size-4" />
        ) : (
          <Plus className="size-4" />
        )}
      </button>
      <input
        dir="auto"
        value={value}
        onChange={(e) => setValue(e.target.value)}
        placeholder={
          asNote
            ? t("addNotePlaceholder")
            : sectionKind === "chores"
              ? t("addChore")
              : t("quickAddPlaceholder")
        }
        className="w-full bg-transparent text-sm outline-none"
      />
    </form>
  );
}

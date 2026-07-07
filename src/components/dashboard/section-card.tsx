"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { formatDistanceToNow } from "date-fns";
import { he, enUS } from "date-fns/locale";
import { Plus } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useIdentity } from "@/lib/identity";
import { useLocaleStore, useT } from "@/lib/i18n/store";
import { Card } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { Button } from "@/components/ui/button";
import type { Section } from "@/types/domain";

export function SectionCard({ section }: { section: Section }) {
  const tasks = useAppStore((s) => s.tasks);
  const chores = useAppStore((s) => s.chores);
  const createTask = useAppStore((s) => s.createTask);
  const actingMemberId = useIdentity((s) => s.actingMemberId);
  const locale = useLocaleStore((s) => s.locale);
  const t = useT();
  const [quickAdding, setQuickAdding] = useState(false);
  const [value, setValue] = useState("");

  const stats = useMemo(() => {
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

  const progress = stats.total > 0 ? Math.round((stats.completed / stats.total) * 100) : 0;

  return (
    <Card className="group relative gap-3 overflow-hidden p-4 transition-shadow hover:shadow-lg">
      <Link href={`/section/${section.id}`} className="absolute inset-0" aria-label={section.name} />
      <div className="pointer-events-none flex items-start justify-between">
        <div className="flex items-center gap-2 text-lg font-semibold">
          <span className="text-2xl">{section.emoji}</span>
          <span dir="auto">{section.name}</span>
        </div>
      </div>

      <Progress value={progress} className="pointer-events-none h-1.5" />

      <div className="pointer-events-none flex items-center justify-between text-xs text-muted-foreground">
        <span>
          {stats.pending} {t("pending")} · {stats.completed} {t("completed")}
        </span>
        {stats.lastEdited && (
          <span>
            {formatDistanceToNow(new Date(stats.lastEdited), { addSuffix: true, locale: locale === "he" ? he : enUS })}
          </span>
        )}
      </div>

      {section.kind !== "chores" && (
        <div className="relative z-10 pointer-events-auto">
          {quickAdding ? (
            <form
              className="flex gap-1.5"
              onSubmit={(e) => {
                e.preventDefault();
                if (!value.trim()) return;
                void createTask({ sectionId: section.id, title: value.trim(), createdBy: actingMemberId });
                setValue("");
                setQuickAdding(false);
              }}
            >
              <input
                autoFocus
                dir="auto"
                value={value}
                onChange={(e) => setValue(e.target.value)}
                onBlur={() => !value && setQuickAdding(false)}
                onClick={(e) => e.stopPropagation()}
                placeholder={t("quickAddPlaceholder")}
                className="w-full rounded-md border bg-background px-2 py-1 text-xs outline-none focus:ring-2 focus:ring-ring"
              />
            </form>
          ) : (
            <Button
              variant="ghost"
              size="sm"
              className="h-6 gap-1 px-2 text-xs text-muted-foreground"
              onClick={(e) => {
                e.preventDefault();
                setQuickAdding(true);
              }}
            >
              <Plus className="size-3" />
              {t("quickAdd")}
            </Button>
          )}
        </div>
      )}
    </Card>
  );
}

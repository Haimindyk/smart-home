"use client";

import { forwardRef, useState } from "react";
import { useSortable } from "@dnd-kit/sortable";
import { GripVertical, MoreVertical, Pencil, Trash2 } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import { useSectionStats } from "@/lib/hooks/use-section-stats";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Progress } from "@/components/ui/progress";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { TaskList } from "@/components/tasks/task-list";
import { ChoreQuickAdd } from "@/components/chores/chore-quick-add";
import { ChoreRow } from "@/components/chores/chore-row";
import { sortByPosition } from "@/lib/ordering/rank";
import { cn } from "@/lib/utils";
import type { Section, SectionKind } from "@/types/domain";

const KIND_GRADIENT: Record<SectionKind, string> = {
  tasks: "from-indigo-400 to-violet-500",
  shopping: "from-emerald-400 to-teal-500",
  chores: "from-amber-400 to-orange-500",
};

type DragHandleProps = Partial<Pick<ReturnType<typeof useSortable>, "attributes" | "listeners">>;

export const SectionPanel = forwardRef<HTMLDivElement, { section: Section; dragHandleProps?: DragHandleProps; style?: React.CSSProperties }>(
  function SectionPanel({ section, dragHandleProps, style }, ref) {
    const renameSection = useAppStore((s) => s.renameSection);
    const deleteSection = useAppStore((s) => s.deleteSection);
    const chores = useAppStore((s) => s.chores);
    const stats = useSectionStats(section);
    const t = useT();
    const [renaming, setRenaming] = useState(false);
    const [name, setName] = useState(section.name);

    const progress = stats.total > 0 ? Math.round((stats.completed / stats.total) * 100) : 0;

    const choreItems =
      section.kind === "chores"
        ? sortByPosition(Object.values(chores).filter((c) => c.section_id === section.id && !c.deleted_at))
        : [];
    const dueChores = choreItems.filter((c) => new Date(c.next_due_at).getTime() <= Date.now());
    const notDueChores = choreItems.filter((c) => new Date(c.next_due_at).getTime() > Date.now());

    return (
      <div
        ref={ref}
        id={`section-${section.id}`}
        style={style}
        className="glass scroll-mt-32 rounded-3xl p-4 ring-1 ring-border/60 sm:p-5"
      >
        <div className="mb-3 flex items-center gap-2.5">
          {dragHandleProps && (
            <button
              {...dragHandleProps.attributes}
              {...dragHandleProps.listeners}
              className="cursor-grab touch-none text-muted-foreground/50 hover:text-muted-foreground"
              aria-label="Drag"
            >
              <GripVertical className="size-4" />
            </button>
          )}
          <div
            className={cn(
              "flex size-9 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br text-lg shadow-inner",
              KIND_GRADIENT[section.kind]
            )}
          >
            {section.emoji}
          </div>

          {renaming ? (
            <Input
              autoFocus
              dir="auto"
              value={name}
              onChange={(e) => setName(e.target.value)}
              onBlur={() => {
                if (name.trim()) void renameSection(section.id, name.trim(), section.emoji ?? undefined);
                setRenaming(false);
              }}
              onKeyDown={(e) => e.key === "Enter" && e.currentTarget.blur()}
              className="h-8 flex-1 text-base font-semibold"
            />
          ) : (
            <h2 dir="auto" className="flex-1 truncate text-lg font-bold tracking-tight">
              {section.name}
            </h2>
          )}

          <span className="hidden shrink-0 text-xs text-muted-foreground sm:inline">
            {stats.pending} {t("pending")} · {stats.completed} {t("completed")}
          </span>

          <DropdownMenu>
            <DropdownMenuTrigger render={<Button variant="ghost" size="icon" className="size-7 shrink-0" />}>
              <MoreVertical className="size-4" />
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem
                onClick={() => {
                  setName(section.name);
                  setRenaming(true);
                }}
              >
                <Pencil className="size-4" /> {t("rename")}
              </DropdownMenuItem>
              <DropdownMenuItem variant="destructive" onClick={() => void deleteSection(section.id)}>
                <Trash2 className="size-4" /> {t("delete")}
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>

        <Progress
          value={progress}
          className="mb-4 h-1.5 bg-muted/70 [&>div]:bg-gradient-to-r [&>div]:from-indigo-400 [&>div]:to-violet-500"
        />

        {section.description && (
          <p dir="auto" className="mb-3 rounded-xl bg-muted/60 px-3 py-2 text-sm text-muted-foreground">
            {section.description}
          </p>
        )}

        {section.kind === "chores" ? (
          <div className="flex flex-col gap-2">
            <ChoreQuickAdd sectionId={section.id} />
            {dueChores.map((chore) => (
              <ChoreRow key={chore.id} chore={chore} />
            ))}
            {notDueChores.map((chore) => (
              <ChoreRow key={chore.id} chore={chore} />
            ))}
          </div>
        ) : (
          <TaskList section={section} />
        )}
      </div>
    );
  }
);

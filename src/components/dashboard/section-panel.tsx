"use client";

import { forwardRef, useState } from "react";
import { useSortable } from "@dnd-kit/sortable";
import { GripVertical, MoreVertical, NotebookPen, Pencil, Trash2 } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import { useSectionStats } from "@/lib/hooks/use-section-stats";
import { useNow } from "@/lib/hooks/use-now";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
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

// Flat, solid category colors (no gradients) — distinct hues for wayfinding
// between section kinds, kept separate from the app's own accent color.
const KIND_COLOR: Record<SectionKind, string> = {
  tasks: "bg-indigo-500",
  shopping: "bg-emerald-500",
  chores: "bg-rose-500",
  info: "bg-sky-500",
};

type DragHandleProps = Partial<Pick<ReturnType<typeof useSortable>, "attributes" | "listeners">>;

export const SectionPanel = forwardRef<HTMLDivElement, { section: Section; dragHandleProps?: DragHandleProps; style?: React.CSSProperties }>(
  function SectionPanel({ section, dragHandleProps, style }, ref) {
    const renameSection = useAppStore((s) => s.renameSection);
    const deleteSection = useAppStore((s) => s.deleteSection);
    const updateSectionNote = useAppStore((s) => s.updateSectionNote);
    const chores = useAppStore((s) => s.chores);
    const stats = useSectionStats(section);
    const t = useT();
    const [renaming, setRenaming] = useState(false);
    const [name, setName] = useState(section.name);
    const [editingNote, setEditingNote] = useState(false);
    const [note, setNote] = useState(section.description ?? "");
    const now = useNow();

    const progress = stats.total > 0 ? Math.round((stats.completed / stats.total) * 100) : 0;

    const choreItems =
      section.kind === "chores"
        ? sortByPosition(Object.values(chores).filter((c) => c.section_id === section.id && !c.deleted_at))
        : [];
    const dueChores = choreItems.filter((c) => new Date(c.next_due_at).getTime() <= now);
    const notDueChores = choreItems.filter((c) => new Date(c.next_due_at).getTime() > now);

    return (
      <div
        ref={ref}
        id={`section-${section.id}`}
        style={style}
        className="glass surface-shadow relative scroll-mt-32 overflow-hidden rounded-3xl p-4 ring-1 ring-border/40 sm:p-5"
      >
        <div className={cn("absolute inset-x-0 top-0 h-1.5", KIND_COLOR[section.kind])} />
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
          <div className="rounded-2xl bg-black/5 p-1 ring-1 ring-black/5 dark:bg-white/5 dark:ring-white/10">
            <div
              className={cn(
                "flex size-8 shrink-0 items-center justify-center rounded-xl text-lg shadow-[inset_0_1px_1px_rgba(255,255,255,0.25)]",
                KIND_COLOR[section.kind]
              )}
            >
              {section.emoji}
            </div>
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
            <h2 dir="auto" className="flex-1 truncate text-xl font-bold tracking-tight">
              {section.name}
            </h2>
          )}

          {section.kind !== "info" && (
            <span className="hidden shrink-0 text-xs tabular-nums text-muted-foreground sm:inline">
              {stats.pending} {t("pending")} · {stats.completed} {t("completed")}
            </span>
          )}

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
              <DropdownMenuItem
                onClick={() => {
                  setNote(section.description ?? "");
                  setEditingNote(true);
                }}
              >
                <NotebookPen className="size-4" /> {t("editNote")}
              </DropdownMenuItem>
              <DropdownMenuItem variant="destructive" onClick={() => void deleteSection(section.id)}>
                <Trash2 className="size-4" /> {t("delete")}
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>

        {section.kind !== "info" && (
          <Progress
            value={progress}
            className="mb-4 h-1.5 bg-muted/70 [&>div]:bg-primary"
          />
        )}

        {editingNote ? (
          <Textarea
            autoFocus
            dir="auto"
            value={note}
            onChange={(e) => setNote(e.target.value)}
            onBlur={() => {
              void updateSectionNote(section.id, note.trim() || null);
              setEditingNote(false);
            }}
            placeholder={t("sectionNotePlaceholder")}
            rows={2}
            className="mb-3 text-sm"
          />
        ) : (
          section.description && (
            <button
              dir="auto"
              onClick={() => {
                setNote(section.description ?? "");
                setEditingNote(true);
              }}
              className="mb-3 w-full rounded-xl bg-muted/60 px-3 py-2 text-start text-sm text-muted-foreground transition-colors hover:bg-muted"
            >
              {section.description}
            </button>
          )
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

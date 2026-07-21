"use client";

import { useRef, useState } from "react";
import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { ChevronDown, ChevronRight, GripVertical, Plus, Trash2 } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useIdentity } from "@/lib/identity";
import { useLocaleStore, useT } from "@/lib/i18n/store";
import { Checkbox } from "@/components/ui/checkbox";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { LinkifiedText } from "@/components/common/bidi-text";
import { AssigneeBadge } from "@/components/tasks/assignee-badge";
import { cn } from "@/lib/utils";
import type { TaskNode, SectionKind } from "@/types/domain";

const PRIORITY_COLOR = ["", "bg-blue-500", "bg-amber-500", "bg-red-500"];

/** Touch devices have no hover, so hover-revealed controls (drag handle, add
 * subtask) need a resting-visible fallback there — `pointer-coarse:` and
 * `group-hover:` are mutually exclusive in practice (coarse-pointer devices
 * don't fire real hover), so there's no ordering conflict between them. */
const TOUCH_VISIBLE = "opacity-0 group-hover:opacity-100 pointer-coarse:opacity-60";

const SWIPE_REVEAL_WIDTH = 72;

/** Swipe-right-to-delete, physical direction regardless of RTL/LTR (a
 * translateX offset always moves right on screen either way). Reveals a
 * delete button on the row's left edge — the area uncovered as the content
 * slides right. Tracks raw pointer deltas rather than touch events so it
 * works with mouse drags too; `touch-action: pan-y` lets vertical scrolling
 * keep working natively while this handles the horizontal axis in JS. */
function SwipeRevealDelete({ onDelete, ariaLabel, children }: { onDelete: () => void; ariaLabel: string; children: React.ReactNode }) {
  const [offsetX, setOffsetX] = useState(0);
  const [open, setOpen] = useState(false);
  const [dragging, setDragging] = useState(false);
  const startRef = useRef({ x: 0, y: 0, offset: 0 });
  const axisRef = useRef<"horizontal" | "vertical" | null>(null);
  // A horizontal drag's release still fires a trailing native "click" on the
  // same element (mousedown+mouseup on one target = click, regardless of how
  // far the pointer travelled in between) — without this, that trailing
  // click would immediately re-close what the drag just opened.
  const suppressNextClickRef = useRef(false);

  function onPointerDown(e: React.PointerEvent) {
    if (!e.isPrimary) return;
    e.currentTarget.setPointerCapture(e.pointerId);
    startRef.current = { x: e.clientX, y: e.clientY, offset: offsetX };
    axisRef.current = null;
    setDragging(true);
  }

  function onPointerMove(e: React.PointerEvent) {
    if (!dragging) return;
    const deltaX = e.clientX - startRef.current.x;
    const deltaY = e.clientY - startRef.current.y;
    if (axisRef.current === null && Math.hypot(deltaX, deltaY) > 8) {
      axisRef.current = Math.abs(deltaX) > Math.abs(deltaY) ? "horizontal" : "vertical";
    }
    if (axisRef.current !== "horizontal") return;
    setOffsetX(Math.min(SWIPE_REVEAL_WIDTH, Math.max(0, startRef.current.offset + deltaX)));
  }

  function endDrag() {
    if (!dragging) return;
    setDragging(false);
    if (axisRef.current === "horizontal") {
      suppressNextClickRef.current = true;
      const shouldOpen = offsetX > SWIPE_REVEAL_WIDTH / 2;
      setOffsetX(shouldOpen ? SWIPE_REVEAL_WIDTH : 0);
      setOpen(shouldOpen);
    }
  }

  function close() {
    setOffsetX(0);
    setOpen(false);
  }

  return (
    <div className="relative overflow-hidden rounded-xl">
      <button
        type="button"
        onClick={onDelete}
        aria-label={ariaLabel}
        className="absolute inset-y-0 left-0 flex items-center justify-center bg-destructive text-destructive-foreground"
        style={{ width: SWIPE_REVEAL_WIDTH }}
      >
        <Trash2 className="size-5" />
      </button>
      <div
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={endDrag}
        onPointerCancel={endDrag}
        onClickCapture={(e) => {
          if (suppressNextClickRef.current) {
            suppressNextClickRef.current = false;
            e.preventDefault();
            e.stopPropagation();
            return;
          }
          if (open) {
            e.preventDefault();
            e.stopPropagation();
            close();
          }
        }}
        style={{
          transform: `translateX(${offsetX}px)`,
          transition: dragging ? "none" : "transform 200ms ease-out",
          touchAction: "pan-y",
        }}
        className="relative bg-card"
      >
        {children}
      </div>
    </div>
  );
}

function dueUrgency(dueAt: string, isCompleted: boolean): "overdue" | "today" | "future" {
  if (isCompleted) return "future";
  const due = new Date(dueAt);
  const dueDay = new Date(due.getFullYear(), due.getMonth(), due.getDate()).getTime();
  const today = new Date();
  const todayDay = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
  if (dueDay < todayDay) return "overdue";
  if (dueDay === todayDay) return "today";
  return "future";
}

/** Top-level task row: participates in the section's drag-to-reorder list. */
export function TaskRow({
  node,
  sectionKind,
  onOpenEditor,
}: {
  node: TaskNode;
  sectionKind: SectionKind;
  onOpenEditor: (taskId: string) => void;
}) {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: node.id });
  const style = { transform: CSS.Transform.toString(transform), transition };

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={cn("rounded-lg", isDragging && "opacity-50")}
    >
      <TaskRowContent
        node={node}
        sectionKind={sectionKind}
        onOpenEditor={onOpenEditor}
        dragHandleProps={{ attributes, listeners }}
      />
    </div>
  );
}

/** Subtask (any depth): same look, no drag handle — reordering subtasks isn't wired yet. */
function TaskChildRow({
  node,
  sectionKind,
  onOpenEditor,
}: {
  node: TaskNode;
  sectionKind: SectionKind;
  onOpenEditor: (taskId: string) => void;
}) {
  return (
    <TaskRowContent
      node={node}
      sectionKind={sectionKind}
      onOpenEditor={onOpenEditor}
    />
  );
}

type DragHandleProps = Pick<
  ReturnType<typeof useSortable>,
  "attributes" | "listeners"
>;

function TaskRowContent({
  node,
  sectionKind,
  onOpenEditor,
  dragHandleProps,
}: {
  node: TaskNode;
  sectionKind: SectionKind;
  onOpenEditor: (taskId: string) => void;
  dragHandleProps?: DragHandleProps;
}) {
  const toggleTaskCompleted = useAppStore((s) => s.toggleTaskCompleted);
  const softDeleteTask = useAppStore((s) => s.softDeleteTask);
  const createTask = useAppStore((s) => s.createTask);
  const actingMemberId = useIdentity((s) => s.actingMemberId);
  const t = useT();
  const locale = useLocaleStore((s) => s.locale);
  const dateLocale = locale === "he" ? "he-IL" : "en-US";
  const [expanded, setExpanded] = useState(true);
  const [addingSubtask, setAddingSubtask] = useState(false);
  const [subtaskTitle, setSubtaskTitle] = useState("");

  if (node.is_note) {
    return (
      <SwipeRevealDelete onDelete={() => softDeleteTask(node.id)} ariaLabel={t("delete")}>
        <div className="group flex items-center gap-2 rounded-lg px-2 py-2 transition-colors hover:bg-accent/40">
          {dragHandleProps ? (
            <button
              {...dragHandleProps.attributes}
              {...dragHandleProps.listeners}
              className={cn("cursor-grab touch-none", TOUCH_VISIBLE)}
              aria-label={t("drag")}
            >
              <GripVertical className="size-4" />
            </button>
          ) : (
            <span className="w-4" />
          )}
          <button
            className="flex flex-1 items-center gap-2 py-0.5 text-start text-sm font-medium text-muted-foreground"
            onClick={() => onOpenEditor(node.id)}
          >
            {node.emoji && <span>{node.emoji}</span>}
            <LinkifiedText text={node.title} />
          </button>
        </div>
      </SwipeRevealDelete>
    );
  }

  return (
    <div>
      <SwipeRevealDelete onDelete={() => softDeleteTask(node.id)} ariaLabel={t("delete")}>
        <div className="group flex items-center gap-2 rounded-xl px-2.5 py-2.5 transition-colors hover:bg-accent/40">
          {dragHandleProps ? (
            <button
              {...dragHandleProps.attributes}
              {...dragHandleProps.listeners}
              className={cn("cursor-grab touch-none text-muted-foreground", TOUCH_VISIBLE)}
              aria-label={t("drag")}
            >
              <GripVertical className="size-4" />
            </button>
          ) : (
            <span className="w-4" />
          )}

          {node.children.length > 0 ? (
            <button
              onClick={() => setExpanded((e) => !e)}
              className="text-muted-foreground"
              aria-label={expanded ? t("collapse") : t("expand")}
              aria-expanded={expanded}
            >
              {expanded ? (
                <ChevronDown className="size-4" />
              ) : (
                <ChevronRight className="size-4 rtl:rotate-180" />
              )}
            </button>
          ) : (
            <span className="w-4" />
          )}

          <Checkbox
            checked={node.is_completed}
            onCheckedChange={() => toggleTaskCompleted(node.id, actingMemberId)}
            className="size-5 rounded-full"
            aria-label={node.title || t("toggleComplete")}
          />

          <button
            className="flex flex-1 flex-col items-start gap-1 py-0.5 text-start"
            onClick={() => onOpenEditor(node.id)}
          >
            {/* Title on its own line so a short title never has to share width
                (and shrink into a wrap) with the badges below it — that fight
                for space was both causing short titles to wrap unnecessarily
                and making the badges' vertical position shift depending on how
                many lines the title happened to wrap to. */}
            <span className="flex w-full items-center gap-2">
              {node.priority ? (
                <span
                  className={cn(
                    "size-1.5 shrink-0 rounded-full",
                    PRIORITY_COLOR[node.priority],
                  )}
                />
              ) : null}
              {node.emoji && <span>{node.emoji}</span>}
              <LinkifiedText
                text={node.title || "…"}
                className={cn(
                  "text-sm",
                  node.is_completed && "text-muted-foreground line-through",
                )}
              />
            </span>
            {(node.quantity || node.due_at) && (
              <span className="flex flex-wrap items-center gap-1.5">
                {node.quantity ? (
                  <Badge variant="secondary" className="h-5 text-xs">
                    ×{node.quantity}
                    {node.unit ?? ""}
                  </Badge>
                ) : null}
                {node.due_at && (
                  <Badge
                    variant="outline"
                    className={cn(
                      "h-5 text-xs",
                      dueUrgency(node.due_at, node.is_completed) === "overdue" &&
                        "border-destructive/40 bg-destructive/10 text-destructive",
                      dueUrgency(node.due_at, node.is_completed) === "today" &&
                        "border-primary/40 bg-primary/10 font-semibold text-primary"
                    )}
                  >
                    {new Date(node.due_at).toLocaleDateString(dateLocale, {
                      day: "numeric",
                      month: "numeric",
                    })}
                    {node.due_end_at &&
                      new Date(node.due_end_at).toDateString() !== new Date(node.due_at).toDateString() &&
                      ` – ${new Date(node.due_end_at).toLocaleDateString(dateLocale, { day: "numeric", month: "numeric" })}`}
                  </Badge>
                )}
              </span>
            )}
          </button>

          <AssigneeBadge
            assigneeKind={node.assignee_kind}
            assigneeMemberId={node.assignee_member_id}
            assigneeMemberIds={node.assignee_member_ids}
          />

          <Button
            variant="ghost"
            size="icon"
            className={cn("size-6", TOUCH_VISIBLE)}
            onClick={() => setAddingSubtask((v) => !v)}
            aria-label={t("addSubtask")}
          >
            <Plus className="size-3.5" />
          </Button>
        </div>
      </SwipeRevealDelete>

      {addingSubtask && (
        <form
          className="ms-10 flex gap-2 pb-2"
          onSubmit={(e) => {
            e.preventDefault();
            if (!subtaskTitle.trim()) return;
            void createTask({
              sectionId: node.section_id,
              parentTaskId: node.id,
              title: subtaskTitle.trim(),
              createdBy: actingMemberId,
            });
            setSubtaskTitle("");
            setAddingSubtask(false);
          }}
        >
          <input
            autoFocus
            dir="auto"
            value={subtaskTitle}
            onChange={(e) => setSubtaskTitle(e.target.value)}
            onBlur={() => !subtaskTitle && setAddingSubtask(false)}
            placeholder={t("addSubtask")}
            className="w-full rounded-md border bg-transparent px-2 py-1 text-sm outline-none focus:ring-2 focus:ring-ring"
          />
        </form>
      )}

      {expanded && node.children.length > 0 && (
        <div className="ms-6 border-s ps-2">
          {node.children.map((child) => (
            <TaskChildRow
              key={child.id}
              node={child}
              sectionKind={sectionKind}
              onOpenEditor={onOpenEditor}
            />
          ))}
        </div>
      )}
    </div>
  );
}

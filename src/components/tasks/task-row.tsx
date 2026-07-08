"use client";

import { useState } from "react";
import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { ChevronDown, ChevronRight, GripVertical, Plus } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useIdentity } from "@/lib/identity";
import { useT } from "@/lib/i18n/store";
import { Checkbox } from "@/components/ui/checkbox";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { LinkifiedText } from "@/components/common/bidi-text";
import { AssigneeBadge } from "@/components/tasks/assignee-badge";
import { cn } from "@/lib/utils";
import type { TaskNode, SectionKind } from "@/types/domain";

const PRIORITY_COLOR = ["", "bg-blue-500", "bg-amber-500", "bg-red-500"];

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
  const createTask = useAppStore((s) => s.createTask);
  const actingMemberId = useIdentity((s) => s.actingMemberId);
  const t = useT();
  const [expanded, setExpanded] = useState(true);
  const [addingSubtask, setAddingSubtask] = useState(false);
  const [subtaskTitle, setSubtaskTitle] = useState("");

  if (node.is_note) {
    return (
      <div className="group flex items-center gap-2 rounded-lg px-2 py-2 transition-colors hover:bg-accent/40">
        {dragHandleProps ? (
          <button
            {...dragHandleProps.attributes}
            {...dragHandleProps.listeners}
            className="cursor-grab touch-none opacity-0 group-hover:opacity-100"
            aria-label="Drag"
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
    );
  }

  return (
    <div>
      <div className="group flex items-center gap-2 rounded-xl px-2.5 py-2.5 transition-colors hover:bg-accent/40">
        {dragHandleProps ? (
          <button
            {...dragHandleProps.attributes}
            {...dragHandleProps.listeners}
            className="cursor-grab touch-none text-muted-foreground opacity-0 group-hover:opacity-100"
            aria-label="Drag"
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
          >
            {expanded ? (
              <ChevronDown className="size-4" />
            ) : (
              <ChevronRight className="size-4" />
            )}
          </button>
        ) : (
          <span className="w-4" />
        )}

        <Checkbox
          checked={node.is_completed}
          onCheckedChange={() => toggleTaskCompleted(node.id, actingMemberId)}
          className="size-5 rounded-full"
        />

        <button
          className="flex flex-1 items-center gap-2 py-0.5 text-start"
          onClick={() => onOpenEditor(node.id)}
        >
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
          {node.quantity ? (
            <Badge variant="secondary" className="h-5 text-xs">
              ×{node.quantity}
              {node.unit ?? ""}
            </Badge>
          ) : null}
          {node.due_at && (
            <Badge variant="outline" className="h-5 text-xs">
              {new Date(node.due_at).toLocaleDateString("he-IL", {
                day: "numeric",
                month: "numeric",
              })}
            </Badge>
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
          className="size-6 opacity-0 group-hover:opacity-100"
          onClick={() => setAddingSubtask((v) => !v)}
        >
          <Plus className="size-3.5" />
        </Button>
      </div>

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

"use client";

import { useMemo, useState } from "react";
import {
  DndContext,
  closestCenter,
  PointerSensor,
  TouchSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
} from "@dnd-kit/core";
import { SortableContext, verticalListSortingStrategy } from "@dnd-kit/sortable";
import { useAppStore } from "@/lib/store/app-store";
import { useIdentity } from "@/lib/identity";
import { useT } from "@/lib/i18n/store";
import { buildTaskTree } from "@/types/domain";
import type { Section } from "@/types/domain";
import { TaskRow } from "@/components/tasks/task-row";
import { TaskEditorSheet } from "@/components/tasks/task-editor-sheet";
import { QuickAddInput } from "@/components/tasks/quick-add-input";

export function TaskList({ section }: { section: Section }) {
  const tasksById = useAppStore((s) => s.tasks);
  const reorderTask = useAppStore((s) => s.reorderTask);
  const actingMemberId = useIdentity((s) => s.actingMemberId);
  const t = useT();
  const [editingTaskId, setEditingTaskId] = useState<string | null>(null);

  const topLevel = useMemo(() => {
    const all = Object.values(tasksById).filter((task) => task.section_id === section.id && !task.deleted_at);
    return buildTaskTree(all);
  }, [tasksById, section.id]);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 150, tolerance: 8 } })
  );

  function handleDragEnd(event: DragEndEvent) {
    const { active, over } = event;
    if (!over || active.id === over.id) return;

    const ids = topLevel.map((n) => n.id);
    const fromIndex = ids.indexOf(String(active.id));
    const toIndex = ids.indexOf(String(over.id));
    if (fromIndex === -1 || toIndex === -1) return;

    const reordered = [...ids];
    reordered.splice(fromIndex, 1);
    reordered.splice(toIndex, 0, String(active.id));
    const newIndex = reordered.indexOf(String(active.id));
    const beforeId = newIndex > 0 ? reordered[newIndex - 1] : null;
    const afterId = newIndex < reordered.length - 1 ? reordered[newIndex + 1] : null;

    void reorderTask(String(active.id), section.id, null, beforeId, afterId);
  }

  return (
    <div className="flex flex-col gap-1">
      <QuickAddInput sectionId={section.id} sectionKind={section.kind} createdBy={actingMemberId} />

      {topLevel.length === 0 && <p className="py-8 text-center text-sm text-muted-foreground">{t("noTasksYet")}</p>}

      <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
        <SortableContext items={topLevel.map((n) => n.id)} strategy={verticalListSortingStrategy}>
          {topLevel.map((node) => (
            <TaskRow key={node.id} node={node} sectionKind={section.kind} onOpenEditor={setEditingTaskId} />
          ))}
        </SortableContext>
      </DndContext>

      <TaskEditorSheet taskId={editingTaskId} sectionKind={section.kind} onOpenChange={(open) => !open && setEditingTaskId(null)} />
    </div>
  );
}

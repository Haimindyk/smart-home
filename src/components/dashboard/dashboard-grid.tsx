"use client";

import { useMemo } from "react";
import {
  DndContext,
  closestCenter,
  PointerSensor,
  TouchSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
} from "@dnd-kit/core";
import { SortableContext, useSortable, rectSortingStrategy } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { useAppStore } from "@/lib/store/app-store";
import { sortByPosition } from "@/lib/ordering/rank";
import { SectionCard } from "@/components/dashboard/section-card";
import type { Section } from "@/types/domain";

function SortableSectionCard({ section }: { section: Section }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: section.id });
  const style = { transform: CSS.Transform.toString(transform), transition, opacity: isDragging ? 0.5 : 1 };

  return (
    <div ref={setNodeRef} style={style} {...attributes} {...listeners}>
      <SectionCard section={section} />
    </div>
  );
}

export function DashboardGrid() {
  const sections = useAppStore((s) => s.sections);
  const reorderSection = useAppStore((s) => s.reorderSection);

  const ordered = useMemo(
    () => sortByPosition(Object.values(sections).filter((s) => !s.deleted_at)),
    [sections]
  );

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 200, tolerance: 8 } })
  );

  function handleDragEnd(event: DragEndEvent) {
    const { active, over } = event;
    if (!over || active.id === over.id) return;

    const ids = ordered.map((s) => s.id);
    const fromIndex = ids.indexOf(String(active.id));
    const toIndex = ids.indexOf(String(over.id));
    if (fromIndex === -1 || toIndex === -1) return;

    const reordered = [...ids];
    reordered.splice(fromIndex, 1);
    reordered.splice(toIndex, 0, String(active.id));
    const newIndex = reordered.indexOf(String(active.id));
    const beforeId = newIndex > 0 ? reordered[newIndex - 1] : null;
    const afterId = newIndex < reordered.length - 1 ? reordered[newIndex + 1] : null;

    void reorderSection(String(active.id), beforeId, afterId);
  }

  return (
    <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
      <SortableContext items={ordered.map((s) => s.id)} strategy={rectSortingStrategy}>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {ordered.map((section) => (
            <SortableSectionCard key={section.id} section={section} />
          ))}
        </div>
      </SortableContext>
    </DndContext>
  );
}

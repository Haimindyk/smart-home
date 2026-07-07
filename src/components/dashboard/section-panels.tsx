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
import { SortableContext, useSortable, verticalListSortingStrategy } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { useAppStore } from "@/lib/store/app-store";
import { sortByPosition } from "@/lib/ordering/rank";
import { SectionPanel } from "@/components/dashboard/section-panel";
import type { Section } from "@/types/domain";

function SortablePanel({ section, index }: { section: Section; index: number }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: section.id });
  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.6 : 1,
    animationDelay: `${Math.min(index, 8) * 40}ms`,
  };

  return (
    <div className="animate-in fade-in slide-in-from-bottom-2 fill-mode-backwards duration-500">
      <SectionPanel section={section} dragHandleProps={{ attributes, listeners }} style={style} ref={setNodeRef} />
    </div>
  );
}

export function SectionPanels({ sections }: { sections: Section[] }) {
  const reorderSection = useAppStore((s) => s.reorderSection);
  const ordered = useMemo(() => sortByPosition(sections), [sections]);

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
      <SortableContext items={ordered.map((s) => s.id)} strategy={verticalListSortingStrategy}>
        <div className="flex flex-col gap-4">
          {ordered.map((section, index) => (
            <SortablePanel key={section.id} section={section} index={index} />
          ))}
        </div>
      </SortableContext>
    </DndContext>
  );
}

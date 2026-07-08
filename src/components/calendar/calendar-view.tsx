"use client";

import { useMemo, useState } from "react";
import { Plus } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useT, useLocaleStore } from "@/lib/i18n/store";
import { Button } from "@/components/ui/button";
import { Calendar } from "@/components/ui/calendar";
import { EventDialog } from "@/components/calendar/event-dialog";
import { nextOccurrence, dateKey } from "@/lib/calendar/occurrences";
import type { FamilyEvent } from "@/types/domain";
import { he as heLocale, enUS } from "react-day-picker/locale";

type CalendarItem = {
  id: string;
  date: Date;
  title: string;
  emoji: string | null;
  kind: "event" | "task";
  event?: FamilyEvent;
};

export function CalendarView() {
  const familyEvents = useAppStore((s) => s.familyEvents);
  const tasks = useAppStore((s) => s.tasks);
  const locale = useLocaleStore((s) => s.locale);
  const t = useT();

  const [month, setMonth] = useState<Date>(() => new Date());
  const [selectedDate, setSelectedDate] = useState<Date>(() => new Date());
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingEvent, setEditingEvent] = useState<FamilyEvent | null>(null);

  const itemsByDate = useMemo(() => {
    const map = new Map<string, CalendarItem[]>();
    const add = (item: CalendarItem) => {
      const key = dateKey(item.date);
      const list = map.get(key) ?? [];
      list.push(item);
      map.set(key, list);
    };

    for (const event of Object.values(familyEvents)) {
      if (event.deleted_at) continue;
      const occurrence = nextOccurrence(event.event_date, event.recurrence, new Date(month.getFullYear(), month.getMonth(), 1));
      // Only place the occurrence if it actually falls in the displayed month —
      // a yearly event whose anchor month differs from the one shown has no
      // occurrence in this month at all.
      if (occurrence.getFullYear() === month.getFullYear() && occurrence.getMonth() === month.getMonth()) {
        add({ id: event.id, date: occurrence, title: event.title, emoji: event.emoji, kind: "event", event });
      }
    }

    for (const task of Object.values(tasks)) {
      if (task.deleted_at || task.is_note || !task.due_at) continue;
      const due = new Date(task.due_at);
      if (due.getFullYear() === month.getFullYear() && due.getMonth() === month.getMonth()) {
        add({ id: task.id, date: due, title: task.title, emoji: task.emoji, kind: "task" });
      }
    }

    return map;
  }, [familyEvents, tasks, month]);

  const upcoming = useMemo(() => {
    const now = new Date();
    const items: CalendarItem[] = [];
    for (const event of Object.values(familyEvents)) {
      if (event.deleted_at) continue;
      items.push({
        id: event.id,
        date: nextOccurrence(event.event_date, event.recurrence, now),
        title: event.title,
        emoji: event.emoji,
        kind: "event",
        event,
      });
    }
    for (const task of Object.values(tasks)) {
      if (task.deleted_at || task.is_note || !task.due_at) continue;
      items.push({ id: task.id, date: new Date(task.due_at), title: task.title, emoji: task.emoji, kind: "task" });
    }
    return items.sort((a, b) => a.date.getTime() - b.date.getTime()).slice(0, 20);
  }, [familyEvents, tasks]);

  const selectedItems = itemsByDate.get(dateKey(selectedDate)) ?? [];

  return (
    <div className="flex flex-col gap-4">
      <div className="glass flex flex-col items-center gap-3 rounded-3xl p-4 ring-1 ring-border/60 sm:p-5">
        <Calendar
          mode="single"
          month={month}
          onMonthChange={setMonth}
          selected={selectedDate}
          onSelect={(d) => d && setSelectedDate(d)}
          locale={locale === "he" ? heLocale : enUS}
          modifiers={{ hasItem: (date) => itemsByDate.has(dateKey(date)) }}
          modifiersClassNames={{
            hasItem: "after:absolute after:bottom-1 after:start-1/2 after:size-1 after:-translate-x-1/2 after:rounded-full after:bg-primary",
          }}
        />

        <div className="flex w-full flex-col gap-2">
          {selectedItems.length === 0 ? (
            <p className="py-2 text-center text-sm text-muted-foreground">{t("noEventsYet")}</p>
          ) : (
            selectedItems.map((item) => (
              <button
                key={`${item.kind}-${item.id}`}
                disabled={item.kind === "task"}
                onClick={() => {
                  if (item.kind === "event" && item.event) {
                    setEditingEvent(item.event);
                    setDialogOpen(true);
                  }
                }}
                className="flex items-center gap-2 rounded-xl bg-muted/50 px-3 py-2 text-start text-sm disabled:cursor-default"
              >
                <span>{item.emoji ?? (item.kind === "task" ? "✅" : "📌")}</span>
                <span dir="auto" className="flex-1">{item.title}</span>
              </button>
            ))
          )}
        </div>

        <Button
          className="gap-2"
          onClick={() => {
            setEditingEvent(null);
            setDialogOpen(true);
          }}
        >
          <Plus className="size-4" />
          {t("addEvent")}
        </Button>
      </div>

      <div className="glass flex flex-col gap-2 rounded-3xl p-4 ring-1 ring-border/60 sm:p-5">
        <h2 className="text-sm font-bold tracking-tight">{t("upcomingEvents")}</h2>
        {upcoming.length === 0 ? (
          <p className="py-4 text-center text-sm text-muted-foreground">{t("noEventsYet")}</p>
        ) : (
          upcoming.map((item) => (
            <button
              key={`${item.kind}-${item.id}`}
              disabled={item.kind === "task"}
              onClick={() => {
                if (item.kind === "event" && item.event) {
                  setEditingEvent(item.event);
                  setDialogOpen(true);
                }
              }}
              className="flex items-center gap-2.5 rounded-xl px-2.5 py-2 text-start text-sm hover:bg-accent/40 disabled:cursor-default disabled:hover:bg-transparent"
            >
              <span>{item.emoji ?? (item.kind === "task" ? "✅" : "📌")}</span>
              <span dir="auto" className="flex-1">{item.title}</span>
              <span className="shrink-0 text-xs text-muted-foreground">
                {item.date.toLocaleDateString(locale === "he" ? "he-IL" : "en-US", { day: "numeric", month: "short" })}
              </span>
            </button>
          ))
        )}
      </div>

      <EventDialog open={dialogOpen} onOpenChange={setDialogOpen} event={editingEvent} defaultDate={selectedDate} />
    </div>
  );
}

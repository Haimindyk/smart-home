"use client";

import { useMemo, useState } from "react";
import { Plus } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useT, useLocaleStore } from "@/lib/i18n/store";
import { Button } from "@/components/ui/button";
import { Calendar } from "@/components/ui/calendar";
import { EventDialog } from "@/components/calendar/event-dialog";
import { nextOccurrence, dateKey, spanDays } from "@/lib/calendar/occurrences";
import { addDays, eachDayOfInterval } from "date-fns";
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

    const isInMonth = (date: Date) => date.getFullYear() === month.getFullYear() && date.getMonth() === month.getMonth();

    for (const event of Object.values(familyEvents)) {
      if (event.deleted_at) continue;
      const start = nextOccurrence(event.event_date, event.recurrence, new Date(month.getFullYear(), month.getMonth(), 1));
      const end = addDays(start, spanDays(event.event_date, event.end_date));
      // Only place days that actually fall in the displayed month — a
      // yearly event whose anchor month differs from the one shown (or a
      // multi-day event that only partly overlaps it) has no occurrence
      // days in this month at all, or just some of them.
      for (const day of eachDayOfInterval({ start, end })) {
        if (isInMonth(day)) {
          add({ id: event.id, date: day, title: event.title, emoji: event.emoji, kind: "event", event });
        }
      }
    }

    for (const task of Object.values(tasks)) {
      if (task.deleted_at || task.is_note || !task.due_at) continue;
      const start = new Date(task.due_at);
      const end = task.due_end_at ? new Date(task.due_end_at) : start;
      for (const day of eachDayOfInterval({ start, end })) {
        if (isInMonth(day)) {
          add({ id: task.id, date: day, title: task.title, emoji: task.emoji, kind: "task" });
        }
      }
    }

    return map;
  }, [familyEvents, tasks, month]);

  // Scoped to the currently displayed month, same as the grid's dots — keeps
  // this list and the calendar above it in sync as the user navigates months.
  const upcoming = useMemo(
    () => Array.from(itemsByDate.values()).flat().sort((a, b) => a.date.getTime() - b.date.getTime()),
    [itemsByDate]
  );

  const selectedItems = itemsByDate.get(dateKey(selectedDate)) ?? [];

  return (
    <div className="flex flex-col gap-4">
      <div className="glass surface-shadow flex flex-col items-center gap-3 rounded-3xl p-4 ring-1 ring-border/40 sm:p-5">
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

      <div className="glass surface-shadow flex flex-col gap-2 rounded-3xl p-4 ring-1 ring-border/40 sm:p-5">
        <h2 className="eyebrow mb-1">{t("upcomingEvents")}</h2>
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

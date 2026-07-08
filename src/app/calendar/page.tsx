"use client";

import { AppHeader } from "@/components/nav/app-header";
import { CalendarView } from "@/components/calendar/calendar-view";

export default function CalendarPage() {
  return (
    <div className="flex min-h-full flex-1 flex-col">
      <AppHeader />
      <main className="mx-auto w-full max-w-3xl flex-1 px-4 py-6">
        <CalendarView />
      </main>
    </div>
  );
}

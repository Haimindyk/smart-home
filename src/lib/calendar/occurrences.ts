import type { EventRecurrence } from "@/types/domain";

/** Last valid day-of-month for `year`/`month` (0-indexed month), for clamping Feb 29 etc. */
function clampedDate(year: number, month: number, day: number): Date {
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  return new Date(year, month, Math.min(day, daysInMonth));
}

/**
 * Next real-world occurrence of a family event on/after `asOf`. Mirrors
 * public.family_event_next_occurrence() in migration 0010 — one-off events
 * return their fixed date, yearly ones roll the month/day forward to the
 * current (or next) year, clamping Feb 29 into non-leap years.
 */
export function nextOccurrence(eventDate: string, recurrence: EventRecurrence, asOf: Date = new Date()): Date {
  const [y, m, d] = eventDate.split("-").map(Number);
  if (recurrence !== "yearly") return new Date(y, m - 1, d);

  const asOfMidnight = new Date(asOf.getFullYear(), asOf.getMonth(), asOf.getDate());
  let candidate = clampedDate(asOfMidnight.getFullYear(), m - 1, d);
  if (candidate < asOfMidnight) {
    candidate = clampedDate(asOfMidnight.getFullYear() + 1, m - 1, d);
  }
  return candidate;
}

export function dateKey(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

/** Whole days between two "yyyy-MM-dd" dates — used to carry a multi-day
 * event's span forward onto a rolled-forward yearly occurrence. */
export function spanDays(startDate: string, endDate: string | null): number {
  if (!endDate) return 0;
  const [sy, sm, sd] = startDate.split("-").map(Number);
  const [ey, em, ed] = endDate.split("-").map(Number);
  const start = new Date(sy, sm - 1, sd);
  const end = new Date(ey, em - 1, ed);
  return Math.round((end.getTime() - start.getTime()) / 86_400_000);
}

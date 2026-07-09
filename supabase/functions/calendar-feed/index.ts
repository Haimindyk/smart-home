// A public, read-only iCalendar (RFC 5545) feed of the household's
// calendar — family_events AND tasks/items that carry a due date, mirroring
// exactly what src/components/calendar/calendar-view.tsx shows inside the
// app (that view merges both sources; this feed originally only read
// family_events, so trips/appointments set via a task's due date were
// silently missing from the exported feed even though they show up in the
// in-app calendar).
//
// Any member can subscribe from Google/Apple/Outlook Calendar instead of
// only ever seeing events inside this app. Matches this app's whole
// philosophy — anyone with the URL can read it, no login, same as
// everything else (see 0002_open_access.sql) — subscription URLs from
// calendar apps can't easily carry a custom Authorization header anyway, so
// this had to be public to work at all.
//
// This is a Deno module (Supabase Edge Runtime), not part of the Next.js
// app's TypeScript project — see tsconfig.json / eslint.config.mjs, both of
// which exclude supabase/functions/**. Deployed with verify_jwt disabled,
// same reasoning as supabase/functions/assistant.

import { createClient } from "npm:@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

type IcsItem = {
  uid: string;
  title: string;
  emoji: string | null;
  /** "YYYY-MM-DD", already in the household's local calendar day. */
  startDate: string;
  endDate: string;
  recurrence: "none" | "yearly";
  notes: string | null;
  updatedAt: string;
};

type FamilyEventRow = {
  id: string;
  title: string;
  emoji: string | null;
  event_date: string;
  end_date: string | null;
  recurrence: string;
  notes: string | null;
  updated_at: string;
};

type TaskDueRow = {
  id: string;
  title: string;
  emoji: string | null;
  due_at: string;
  due_end_at: string | null;
  notes: string | null;
  updated_at: string;
};

/** Escapes text per RFC 5545 §3.3.11 — backslash, then the characters that
 * become meaningful once escaped, so ordering matters. */
function escapeIcsText(text: string): string {
  return text.replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\n/g, "\\n");
}

/** "2026-07-09" -> "20260709" */
function toIcsDate(dateStr: string): string {
  return dateStr.replaceAll("-", "");
}

/** One day after `dateStr`, in the same "YYYYMMDD" shape — DTEND on an
 * all-day VEVENT is exclusive, so a same-day event needs DTEND = day + 1. */
function dayAfter(dateStr: string): string {
  const [y, m, d] = dateStr.split("-").map(Number);
  const next = new Date(Date.UTC(y, m - 1, d + 1));
  return `${next.getUTCFullYear()}${String(next.getUTCMonth() + 1).padStart(2, "0")}${String(next.getUTCDate()).padStart(2, "0")}`;
}

/** Normalizes through Date first — Postgres returns timestamptz as
 * "...+00:00", not the "...Z" shape toISOString() always produces, and
 * naively string-replacing the former leaves a malformed "+0000Z" tail. */
function toIcsTimestamp(iso: string): string {
  return new Date(iso).toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");
}

/** Tasks store due_at/due_end_at as timestamptz, not a plain date, so a
 * naive UTC read can land on the wrong calendar day (e.g. 21:00 UTC is
 * already the next day in Israel). Converting through the household's
 * timezone matches what the in-app calendar (which reads local Date
 * components in the browser) actually shows the user. */
function toIsraelDateStr(iso: string): string {
  return new Date(iso).toLocaleDateString("en-CA", { timeZone: "Asia/Jerusalem" });
}

function buildIcs(items: IcsItem[]): string {
  const lines: string[] = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//K&H Family//Smart Home//HE", "CALSCALE:GREGORIAN", "METHOD:PUBLISH", "X-WR-CALNAME:לוח שנה משפחתי"];

  for (const item of items) {
    const summary = item.emoji ? `${item.emoji} ${item.title}` : item.title;
    lines.push(
      "BEGIN:VEVENT",
      `UID:${item.uid}`,
      `DTSTAMP:${toIcsTimestamp(new Date().toISOString())}`,
      `DTSTART;VALUE=DATE:${toIcsDate(item.startDate)}`,
      `DTEND;VALUE=DATE:${dayAfter(item.endDate)}`,
      `SUMMARY:${escapeIcsText(summary)}`
    );
    if (item.notes) lines.push(`DESCRIPTION:${escapeIcsText(item.notes)}`);
    if (item.recurrence === "yearly") lines.push("RRULE:FREQ=YEARLY");
    lines.push(`LAST-MODIFIED:${toIcsTimestamp(item.updatedAt)}`, "END:VEVENT");
  }

  lines.push("END:VCALENDAR");
  return lines.join("\r\n") + "\r\n";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseAnonKey);

  const [{ data: events, error: eventsError }, { data: tasks, error: tasksError }] = await Promise.all([
    supabase
      .from("family_events")
      .select("id, title, emoji, event_date, end_date, recurrence, notes, updated_at")
      .is("deleted_at", null),
    supabase
      .from("tasks")
      .select("id, title, emoji, due_at, due_end_at, notes, updated_at")
      .is("deleted_at", null)
      .eq("is_note", false)
      .not("due_at", "is", null),
  ]);

  if (eventsError || tasksError) {
    console.error("calendar-feed: query failed", eventsError ?? tasksError);
    return new Response("calendar feed unavailable", { status: 500, headers: CORS_HEADERS });
  }

  const items: IcsItem[] = [
    ...((events ?? []) as FamilyEventRow[]).map((e): IcsItem => ({
      uid: `${e.id}@kh.family`,
      title: e.title,
      emoji: e.emoji,
      startDate: e.event_date,
      endDate: e.end_date ?? e.event_date,
      recurrence: e.recurrence === "yearly" ? "yearly" : "none",
      notes: e.notes,
      updatedAt: e.updated_at,
    })),
    ...((tasks ?? []) as TaskDueRow[]).map((t): IcsItem => {
      const startDate = toIsraelDateStr(t.due_at);
      return {
        uid: `task-${t.id}@kh.family`,
        title: t.title,
        emoji: t.emoji ?? "✅",
        startDate,
        endDate: t.due_end_at ? toIsraelDateStr(t.due_end_at) : startDate,
        recurrence: "none",
        notes: t.notes,
        updatedAt: t.updated_at,
      };
    }),
  ].sort((a, b) => a.startDate.localeCompare(b.startDate));

  const ics = buildIcs(items);

  return new Response(ics, {
    headers: {
      "Content-Type": "text/calendar; charset=utf-8",
      "Cache-Control": "public, max-age=900",
      ...CORS_HEADERS,
    },
  });
});

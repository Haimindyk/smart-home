// A public, read-only iCalendar (RFC 5545) feed of family_events, so any
// member can subscribe from Google/Apple/Outlook Calendar instead of only
// ever seeing events inside this app. Matches this app's whole philosophy —
// anyone with the URL can read it, no login, same as everything else (see
// 0002_open_access.sql) — subscription URLs from calendar apps can't easily
// carry a custom Authorization header anyway, so this had to be public to
// work at all.
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

function buildIcs(events: FamilyEventRow[]): string {
  const lines: string[] = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//K&H Family//Smart Home//HE", "CALSCALE:GREGORIAN", "METHOD:PUBLISH", "X-WR-CALNAME:לוח שנה משפחתי"];

  for (const event of events) {
    const summary = event.emoji ? `${event.emoji} ${event.title}` : event.title;
    lines.push(
      "BEGIN:VEVENT",
      `UID:${event.id}@kh.family`,
      `DTSTAMP:${toIcsTimestamp(new Date().toISOString())}`,
      `DTSTART;VALUE=DATE:${toIcsDate(event.event_date)}`,
      `DTEND;VALUE=DATE:${dayAfter(event.end_date ?? event.event_date)}`,
      `SUMMARY:${escapeIcsText(summary)}`
    );
    if (event.notes) lines.push(`DESCRIPTION:${escapeIcsText(event.notes)}`);
    if (event.recurrence === "yearly") lines.push("RRULE:FREQ=YEARLY");
    lines.push(`LAST-MODIFIED:${toIcsTimestamp(event.updated_at)}`, "END:VEVENT");
  }

  lines.push("END:VCALENDAR");
  return lines.join("\r\n") + "\r\n";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseAnonKey);

  const { data: events, error } = await supabase
    .from("family_events")
    .select("id, title, emoji, event_date, end_date, recurrence, notes, updated_at")
    .is("deleted_at", null)
    .order("event_date", { ascending: true });

  if (error) {
    console.error("calendar-feed: query failed", error);
    return new Response("calendar feed unavailable", { status: 500, headers: CORS_HEADERS });
  }

  const ics = buildIcs((events ?? []) as FamilyEventRow[]);

  return new Response(ics, {
    headers: {
      "Content-Type": "text/calendar; charset=utf-8",
      "Cache-Control": "public, max-age=900",
      ...CORS_HEADERS,
    },
  });
});

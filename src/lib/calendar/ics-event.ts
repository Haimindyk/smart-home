/** Downloads a single event as a standalone .ics file — tapping the
 * resulting file on iOS/Android/desktop typically offers to add it straight
 * to the device's calendar app. This is the per-event counterpart to
 * subscribing to the whole feed (see subscribe-calendar-dialog.tsx): useful
 * when someone just wants one trip or appointment on their own calendar,
 * without subscribing to the household's entire feed. Built client-side
 * from the same Date objects the calendar view already renders — since
 * those were parsed from ISO strings and read via local Date getters,
 * they're already in the browser's timezone, so no manual TZ conversion is
 * needed here (unlike the server-side calendar-feed function, which has no
 * implicit locale). */
function pad(n: number): string {
  return String(n).padStart(2, "0");
}

function toIcsDateFromJs(d: Date): string {
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}`;
}

function escapeIcsText(text: string): string {
  return text.replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\n/g, "\\n");
}

function toIcsTimestampNow(): string {
  return new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");
}

export function downloadEventIcs(input: { title: string; emoji?: string | null; start: Date; end: Date; notes?: string | null }): void {
  const summary = input.emoji ? `${input.emoji} ${input.title}` : input.title;
  const endExclusive = new Date(input.end);
  endExclusive.setDate(endExclusive.getDate() + 1);

  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//K&H Family//Smart Home//HE",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "BEGIN:VEVENT",
    `UID:${crypto.randomUUID()}@kh.family`,
    `DTSTAMP:${toIcsTimestampNow()}`,
    `DTSTART;VALUE=DATE:${toIcsDateFromJs(input.start)}`,
    `DTEND;VALUE=DATE:${toIcsDateFromJs(endExclusive)}`,
    `SUMMARY:${escapeIcsText(summary)}`,
  ];
  if (input.notes) lines.push(`DESCRIPTION:${escapeIcsText(input.notes)}`);
  lines.push("END:VEVENT", "END:VCALENDAR");
  const ics = lines.join("\r\n") + "\r\n";

  const blob = new Blob([ics], { type: "text/calendar;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `${input.title.replace(/[^\p{L}\p{N} ]+/gu, "").trim() || "event"}.ics`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

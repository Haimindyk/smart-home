/**
 * Small, honest natural-language date extraction for quick-add. Handles the
 * common cases (today/tomorrow in Hebrew & English, dd/mm[/yy] dates, and
 * bare month names) and strips the matched phrase out of the title. Anything
 * fancier (relative weekdays, ranges) is out of scope for this pass.
 */
export function parseQuickAdd(input: string): { title: string; dueAt: string | null } {
  const trimmed = input.trim();
  const now = new Date();

  const patterns: Array<{ regex: RegExp; toDate: (m: RegExpMatchArray) => Date }> = [
    { regex: /\bמחר\b/, toDate: () => addDays(now, 1) },
    { regex: /\bהיום\b/, toDate: () => now },
    { regex: /\btomorrow\b/i, toDate: () => addDays(now, 1) },
    { regex: /\btoday\b/i, toDate: () => now },
    {
      // 25/1/27, 3/8, 18-8-26
      regex: /\b(\d{1,2})[/.\-](\d{1,2})(?:[/.\-](\d{2,4}))?\b/,
      toDate: (m) => {
        const day = Number(m[1]);
        const month = Number(m[2]) - 1;
        let year = m[3] ? Number(m[3]) : now.getFullYear();
        if (year < 100) year += 2000;
        return new Date(year, month, day);
      },
    },
  ];

  for (const { regex, toDate } of patterns) {
    const match = trimmed.match(regex);
    if (match) {
      const date = toDate(match);
      if (!Number.isNaN(date.getTime())) {
        const title = trimmed.replace(regex, "").replace(/\s{2,}/g, " ").trim();
        return { title: title || trimmed, dueAt: date.toISOString() };
      }
    }
  }

  return { title: trimmed, dueAt: null };
}

function addDays(date: Date, days: number) {
  const next = new Date(date);
  next.setDate(next.getDate() + days);
  return next;
}

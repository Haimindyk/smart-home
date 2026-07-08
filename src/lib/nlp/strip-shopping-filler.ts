/**
 * Shopping-list items are commonly phrased as an instruction rather than a
 * bare product name — the app's own quick-add placeholder suggests "לקנות
 * חלב מחר" (buy milk tomorrow). Words like "לקנות" have no relation to any
 * product name and dilute a trigram similarity search enough to return zero
 * matches for an otherwise-easy query. Stripped before searching only — the
 * item's stored/displayed title is left exactly as the person typed it.
 */
const FILLER_PREFIX_PATTERNS: RegExp[] = [
  /^צריך\s+לקנות\s+/,
  /^צריכה\s+לקנות\s+/,
  /^לקנות\s+/,
  /^צריך\s+/,
  /^צריכה\s+/,
  /^תביאי?\s+/,
  /^להביא\s+/,
  /^קנה\s+/,
  /^קני\s+/,
  /^buy\s+/i,
  /^get\s+/i,
  /^need\s+/i,
  /^purchase\s+/i,
  /^pick\s+up\s+/i,
];

export function stripShoppingFillerWords(text: string): string {
  let result = text.trim();
  let changed = true;
  // Loop in case of compound phrasing like "צריך לקנות" matching two
  // separate single-word patterns in sequence.
  while (changed) {
    changed = false;
    for (const pattern of FILLER_PREFIX_PATTERNS) {
      const next = result.replace(pattern, "");
      if (next !== result) {
        result = next;
        changed = true;
      }
    }
  }
  // Don't let stripping empty out a title that's *only* a filler word.
  return result.trim() || text.trim();
}

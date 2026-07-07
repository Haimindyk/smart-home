import { generateKeyBetween, generateNKeysBetween } from "fractional-indexing";

/** Rank for a new item appended to the end of a list. */
export function rankAtEnd(lastPosition: string | null | undefined): string {
  return generateKeyBetween(lastPosition ?? null, null);
}

/** Rank for an item moved/inserted between two neighbors (either may be absent at a list edge). */
export function rankBetween(before: string | null | undefined, after: string | null | undefined): string {
  return generateKeyBetween(before ?? null, after ?? null);
}

/** N evenly spaced ranks, useful for seeding an ordered list in one shot. */
export function ranksForCount(count: number): string[] {
  return generateNKeysBetween(null, null, count);
}

export function sortByPosition<T extends { position: string }>(items: T[]): T[] {
  return [...items].sort((a, b) => (a.position < b.position ? -1 : a.position > b.position ? 1 : 0));
}

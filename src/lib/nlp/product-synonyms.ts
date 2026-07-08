/**
 * Groups of Hebrew product-category phrasings that mean the same thing in
 * Israeli grocery retail but share no common words, so trigram similarity
 * search can never bridge them on its own — e.g. Shufersal genuinely sells
 * body wash, just under "תחליב רחצה" ("bathing emulsion") rather than
 * "סבון גוף" ("body soap"), which a chain like Rami Levy uses instead.
 * Add pairs here as real cross-chain naming mismatches get reported.
 */
export const PRODUCT_SYNONYM_GROUPS: string[][] = [["סבון גוף", "תחליב רחצה", "תחליב גוף"]];

/**
 * Expands a search query into itself plus any synonym-substituted variants,
 * so a query using one common phrasing still finds chains that only carry
 * the product under a different (but equivalent) phrasing.
 */
export function expandSynonymQueries(query: string): string[] {
  const variants = new Set<string>([query]);
  for (const group of PRODUCT_SYNONYM_GROUPS) {
    const matchedTerm = group.find((term) => query.includes(term));
    if (!matchedTerm) continue;
    for (const term of group) {
      if (term !== matchedTerm) variants.add(query.replace(matchedTerm, term));
    }
  }
  return Array.from(variants);
}

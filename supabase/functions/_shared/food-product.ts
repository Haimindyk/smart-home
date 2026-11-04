// Open Food Facts values are normalized by the source. Never infer missing
// macros, serving density or label basis from the brand or package appearance.
export function openFoodFactsProduct(raw: unknown, barcode: string) {
  const r = raw as {
    status?: number;
    product?: Record<string, unknown>;
  } | null;
  const p = r?.product;
  if (r?.status !== 1 || !p) return null;
  const n = p.nutriments as Record<string, unknown> | undefined;
  const value = (key: string, max: number) =>
    typeof n?.[key] === "number" &&
    Number.isFinite(n[key]) &&
    n[key] >= 0 &&
    n[key] <= max
      ? (n[key] as number)
      : null;
  const basis =
    p.nutrition_data_per === "100g"
      ? "g"
      : p.nutrition_data_per === "100ml"
        ? "ml"
        : null;
  if (!basis) return null; // Per-serving/unknown basis needs the actual label.
  const kcal = value("energy-kcal_100g", 1000),
    protein = value("proteins_100g", 100),
    carbs = value("carbohydrates_100g", 100),
    fat = value("fat_100g", 100);
  if ([kcal, protein, carbs, fat].some((v) => v === null)) return null;
  const name =
    typeof p.product_name_he === "string" && p.product_name_he.trim()
      ? p.product_name_he
      : p.product_name;
  if (typeof name !== "string" || !name.trim() || name.length > 200)
    return null;
  const sodium = value("sodium_100g", 100);
  return {
    id: `off:${barcode}`,
    name: name.trim(),
    barcode,
    basis,
    source: "openfoodfacts" as const,
    sourceId: `https://world.openfoodfacts.org/product/${barcode}`,
    per100: {
      kcal: kcal!,
      protein: protein!,
      carbs: carbs!,
      fat: fat!,
      fiber: value("fiber_100g", 100),
      sugar: value("sugars_100g", 100),
      saturatedFat: value("saturated-fat_100g", 100),
      sodium: sodium === null ? null : sodium * 1000,
    },
  };
}

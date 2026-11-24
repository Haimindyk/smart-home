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
  // Some products only list energy in kJ: converting the unit is exact (1 kcal = 4.184 kJ), not an inference.
  const kj = value("energy-kj_100g", 4200) ?? value("energy_100g", 4200);
  const kcal = value("energy-kcal_100g", 1000) ??
      (kj === null ? null : Math.round((kj / 4.184) * 10) / 10),
    protein = value("proteins_100g", 100),
    carbs = value("carbohydrates_100g", 100),
    fat = value("fat_100g", 100);
  if (kcal === null) return null;
  // Zero-calorie drinks (for example Sprite Zero) list energy but omit the macros that are zero. At 5 kcal/100 or
  // less, the energy itself bounds every missing macro to about a gram, so a missing value is treated as 0.
  // Any other product with a missing macro still needs the real label.
  const nearZero = kcal <= 5;
  const macro = (v: number | null) => (v === null && nearZero ? 0 : v);
  const [proteinG, carbsG, fatG] = [macro(protein), macro(carbs), macro(fat)];
  if ([proteinG, carbsG, fatG].some((v) => v === null)) return null;
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
      protein: proteinG!,
      carbs: carbsG!,
      fat: fatG!,
      fiber: value("fiber_100g", 100),
      sugar: value("sugars_100g", 100),
      saturatedFat: value("saturated-fat_100g", 100),
      sodium: sodium === null ? null : sodium * 1000,
    },
  };
}

import { expect, it } from "vitest";
import { translatedFoodName, normalizeCompactMeal } from "../../supabase/functions/_shared/wellness-food";
import { applyFoodCorrection } from "../../supabase/functions/_shared/wellness-food-correction";

it("uses schnitzel for observed breaded chicken cutlets/strips, retaining visible sesame", () => {
  expect(translatedFoodName("breaded chicken cutlet with sesame", "עוף מטוגן")).toBe("שניצל עוף בציפוי פירורים ושומשום");
  expect(translatedFoodName("breaded fried chicken strip", "רצועת עוף מטוגנת")).toBe("רצועת שניצל עוף");
  expect(translatedFoodName("breaded turkey strips", "עוף")).toBe("רצועות שניצל הודו");
  expect(translatedFoodName("oven-baked breaded chicken cutlet", "עוף")).toBe("שניצל עוף אפוי");
  expect(translatedFoodName("breaded chicken cutlet", "שניצל עוף אפוי ללא גלוטן")).toBe("שניצל עוף אפוי ללא גלוטן");
});

it("preserves the logged weight and range when correcting fried chicken to schnitzel", () => {
  const per100 = { kcal: 270, protein: 24, carbs: 16, fat: 12, fiber: null, sugar: null, saturatedFat: null, sodium: null };
  const original = { id: "synthetic-item", quantity: 137, quantityRange: { low: 120, high: 160 }, food: { id: "synthetic-food", name: "רצועת עוף מטוגנת", basis: "g", source: "ai", per100 } };
  const [updated] = applyFoodCorrection({ changes: [{ itemRef: "i0", name: "שניצל עוף", newQuantity: null, per100, assumption: "כולל ציפוי וספיגת שמן משוערת" }], additions: [] }, [original], "זה שניצל עוף");
  expect(updated.quantity).toBe(137);
  expect(updated.quantityRange).toEqual(original.quantityRange);
  expect((updated.food as {name:string}).name).toBe("שניצל עוף");
});

it("does not call unbreaded chicken, nuggets, fish or tofu chicken schnitzel", () => {
  for (const [en, he] of [["fried chicken strips", "רצועות עוף מטוגנות"], ["breaded chicken nuggets", "נאגטס עוף"], ["breaded fish fillet", "פילה דג בציפוי"], ["breaded tofu cutlet", "טופו מצופה"]])
    expect(translatedFoodName(en, he)).toBe(he);
});

it("retains preparation details on an otherwise correct canonical translation", () => {
  expect(translatedFoodName("chicken", "שניצל עוף בציפוי פירורים ושומשום")).toBe("שניצל עוף בציפוי פירורים ושומשום");
  expect(translatedFoodName("egg", "ביצה עלומה")).toBe("ביצה עלומה");
  expect(translatedFoodName("chicken", "דג מטוגן")).toBe("עוף");
  expect(translatedFoodName("cucumber", "עגבנייה")).toBe("מלפפון");
  expect(translatedFoodName("constructor", "מזון")).toBe("מזון");
});

it("refines the prepared-food name without changing quantity, bounds or supplied nutrition", () => {
  const result = normalizeCompactMeal({ recipeEstimate: null, foods: [{
    nameEn: "breaded chicken cutlet with sesame", nameHe: "רצועת עוף מטוגנת", cookingFatIncluded: true,
    certainty: "likely", alternatives: [], basis: "g", portion: [130, 110, 150],
    per100: [270, 24, 16, 12, null, null, null, null],
  }], question: "" }, true);
  expect(result.items).toHaveLength(1);
  expect(result.items[0]).toMatchObject({ name: "שניצל עוף בציפוי פירורים ושומשום", quantity: 130, quantityLow: 110, quantityHigh: 150, per100: { kcal: 270, carbs: 16, fat: 12 } });
});

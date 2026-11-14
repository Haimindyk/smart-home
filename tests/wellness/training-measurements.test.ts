import { expect, it } from "vitest";
import { nutritionTrainingItems } from "../../supabase/functions/_shared/training-measurements";

const items = [
  { id: "rice", quantity: 150, food: { name: "אורז", basis: "g", source: "ai", per100: { kcal: 130 } } },
  { id: "fish", quantity: 200, food: { name: "דג", basis: "g", source: "label", per100: { kcal: 180 } } },
];
const measured = [{ itemId: "fish", grams: 110 }, { itemId: "rice", grams: 65 }];

it("uses explicit weights by ingredient identity, without changing the diary or nutrient provenance", () => {
  const result = nutritionTrainingItems(items, true, measured);
  expect(result.map((i) => i.quantity)).toEqual([65, 110]);
  expect(result[0].per100).toEqual(items[0].food.per100);
  expect(result[0].source).toBe("ai"); // Weighing never verifies an AI nutrient value.
  expect(result[1].source).toBe("label");
  expect(items.map((i) => i.quantity)).toEqual([150, 200]);
});

it("rejects checkbox-only claims, missing measurements, duplicate identities and unknown ingredients", () => {
  for (const value of [undefined, [], measured.slice(0, 1), [measured[0], measured[0]], [measured[0], { itemId: "other", grams: 50 }]])
    expect(() => nutritionTrainingItems(items, true, value)).toThrow("training_weights_required");
});

it("rejects unweighed volumes rather than treating ml as grams", () => {
  expect(() => nutritionTrainingItems([{ ...items[0], food: { ...items[0].food, basis: "ml" } }, items[1]], true, measured)).toThrow("training_weights_required");
});

it("rejects zero, negative, nonfinite, text and excessive gram quantities", () => {
  for (const grams of [0, -1, NaN, Infinity, "65", 10001])
    expect(() => nutritionTrainingItems(items, true, [measured[0], { itemId: "rice", grams }])).toThrow("training_weights_required");
});

it("retains ordinary corrected examples without claiming measured weights", () => {
  expect(nutritionTrainingItems(items, false, measured).map((i) => i.quantity)).toEqual([150, 200]);
});

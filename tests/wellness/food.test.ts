import liveMeal from "./meal-photo-live.json";
import { describe, expect, it } from "vitest";
import {
  assertEstimatedFoodMode,
  normalizeFoodEstimate,
  normalizeObservedMeal,
  parseObservations,
} from "../../supabase/functions/_shared/wellness-food";
import { openFoodFactsProduct } from "../../supabase/functions/_shared/food-product";
import { foodFromPrintedLabel } from "../../src/lib/health/product-label";
const nutrients = {
  kcal: 250,
  protein: 10,
  carbs: 30,
  fat: 10,
  fiber: null,
  sugar: null,
  saturatedFat: null,
  sodium: 400,
};
const item = {
  name: "מזון",
  quantity: 2,
  quantityLow: 1,
  quantityHigh: 3,
  basis: "g",
  quantityUnit: "oz",
  per100: nutrients,
  assumption: "rough portion",
};
const raw = (i: unknown = item) => ({
  items: [i],
  needsClarification: false,
  question: "",
});
describe("food identity and unit boundaries", () => {
  it("converts mass units by exact factors without changing per-100 nutrients", () => {
    const result = normalizeFoodEstimate(raw()).items[0];
    expect(result.quantity).toBeCloseTo(56.69904625);
    expect(result.quantityLow).toBeCloseTo(28.349523125);
    expect(result.quantityHigh).toBeCloseTo(85.048569375);
    expect(result.per100.kcal).toBe(250);
    expect(
      normalizeFoodEstimate(
        raw({
          ...item,
          quantityUnit: "kg",
          quantity: 0.15,
          quantityLow: 0.15,
          quantityHigh: 0.15,
        }),
      ).items[0].quantity,
    ).toBe(150);
  });
  it("converts litres only to ml; never guesses density, cup mass or piece size", () => {
    expect(
      normalizeFoodEstimate(
        raw({
          ...item,
          basis: "ml",
          quantityUnit: "l",
          quantity: 0.2,
          quantityLow: 0.2,
          quantityHigh: 0.2,
        }),
      ).items[0].quantity,
    ).toBe(200);
    for (const patch of [
      { quantityUnit: "cups" },
      { quantityUnit: "pieces" },
      { quantityUnit: "ml" },
      { basis: "ml", quantityUnit: "oz" },
    ]) {
      expect(() => normalizeFoodEstimate(raw({ ...item, ...patch }))).toThrow(
        "invalid_output",
      );
    }
  });
  it("locks final names/portions to observed identities, excluding uncertain or duplicated candidates", () => {
    const observed = parseObservations({
      foods: [
        {
          id: "f1",
          nameEn: "tomatoes",
          nameHe: "תפוזים",
          certainty: "likely",
          alternatives: [],
          quantity: 80,
          quantityLow: 40,
          quantityHigh: 120,
          basis: "g",
        },
      ],
      question: "",
    }).foods;
    const ai = {
      ...item,
      name: "תפוזים",
      observationId: "f1",
      quantityUnit: "g",
    };
    const result = normalizeFoodEstimate(raw(ai), observed);
    expect(result.items[0]).toMatchObject({
      name: "עגבניות",
      quantity: 80,
      quantityLow: 40,
      quantityHigh: 120,
    });
    expect(result.needsClarification).toBe(true);
    expect(() =>
      normalizeFoodEstimate(raw(ai), [
        { ...observed[0], certainty: "uncertain" },
      ]),
    ).toThrow();
    expect(() =>
      normalizeFoodEstimate({ ...raw(ai), items: [ai, ai] }, observed),
    ).toThrow();
    expect(() =>
      normalizeFoodEstimate(
        raw({ ...ai, basis: "ml", quantityUnit: "ml" }),
        observed,
      ),
    ).toThrow();
    expect(() =>
      normalizeFoodEstimate(
        raw({ ...ai, observationId: "invented" }),
        observed,
      ),
    ).toThrow();
  });
  it("does not allow label estimation through the AI mode boundary", () => {
    expect(() => assertEstimatedFoodMode("label")).toThrow(
      "label_lookup_required",
    );
    expect(() => assertEstimatedFoodMode("meal")).not.toThrow();
  });
});
describe("printed product data without generative estimates", () => {
  const off = {
    status: 1,
    product: {
      product_name: "Test product",
      nutrition_data_per: "100g",
      product_quantity_unit: "ml",
      nutriments: {
        "energy-kcal_100g": 250,
        proteins_100g: 10,
        carbohydrates_100g: 30,
        fat_100g: 10,
        sodium_100g: 0.4,
      },
    },
  };
  it("keeps the declared nutrient basis despite a different package unit, and converts sodium g to mg", () => {
    const food = openFoodFactsProduct(off, "12345678")!;
    expect(food.basis).toBe("g");
    expect(food.per100.sodium).toBe(400);
    expect(food.per100.fiber).toBeNull();
    expect(food.source).toBe("openfoodfacts");
  });
  it("returns no product for missing required values, ambiguous basis or malformed numbers", () => {
    expect(
      openFoodFactsProduct(
        {
          ...off,
          product: {
            ...off.product,
            nutriments: { ...off.product.nutriments, proteins_100g: null },
          },
        },
        "12345678",
      ),
    ).toBeNull();
    expect(
      openFoodFactsProduct(
        { ...off, product: { ...off.product, nutrition_data_per: "serving" } },
        "12345678",
      ),
    ).toBeNull();
    expect(
      openFoodFactsProduct(
        {
          ...off,
          product: {
            ...off.product,
            nutriments: { ...off.product.nutriments, fat_100g: -1 },
          },
        },
        "12345678",
      ),
    ).toBeNull();
  });
  const printed = {
    name: "מוצר מהאריזה",
    basis: "g" as const,
    printedAmount: "40",
    values: { kcal: "100", protein: "4", carbs: "12", fat: "4", sodium: "160" },
    confirmed: true,
  };
  it("normalizes the actual printed serving, requiring explicit confirmation and all four macros", () => {
    const food = foodFromPrintedLabel(printed);
    expect(food.source).toBe("label");
    expect(food.per100).toMatchObject(nutrients);
    expect(() =>
      foodFromPrintedLabel({ ...printed, confirmed: false }),
    ).toThrow("label_confirmation_required");
    expect(() =>
      foodFromPrintedLabel({
        ...printed,
        values: { ...printed.values, protein: "" },
      }),
    ).toThrow("label_values_required");
    expect(
      foodFromPrintedLabel({
        ...printed,
        values: { ...printed.values, protein: "0" },
      }).per100.protein,
    ).toBe(0);
    expect(() =>
      foodFromPrintedLabel({ ...printed, printedAmount: "0" }),
    ).toThrow();
  });
});

describe("live photo normalization regression", () => {
  it("retains canonical units and known identities, excluding ambiguous protein candidates", () => {
    const result = normalizeObservedMeal(liveMeal.output);
    expect(result.items.map((i) => i.name)).toEqual([
      "חסה",
      "כרוב אדום",
      "בצל ירוק",
      "עגבניות שרי",
      "תירס",
    ]);
    expect(result.items.every((i) => i.basis === "g")).toBe(true);
    expect(result.items.some((i) => /טופו|ביצה/.test(i.name))).toBe(false);
    expect(result.question).toContain("לא נכללו");
    expect(result.question).toContain("טופו");
    expect(result.question).not.toContain("\\u05");
    expect(result.needsClarification).toBe(true);
  });
});

it("converts actual printed kJ, sodium grams and salt grams without model estimates", () => {
  const common = {
    name: "Printed units",
    basis: "g" as const,
    printedAmount: "100",
    confirmed: true,
    values: {
      kcal: "1046",
      protein: "10",
      carbs: "30",
      fat: "10",
      sodium: "1",
    },
  };
  const fromSalt = foodFromPrintedLabel({
    ...common,
    energyUnit: "kJ",
    sodiumUnit: "salt_g",
  });
  expect(fromSalt.per100.kcal).toBeCloseTo(250);
  expect(fromSalt.per100.sodium).toBe(400);
  expect(fromSalt.sourceId).toBe(`label:printed-confirmed:v1:${fromSalt.id}`);
  expect(
    foodFromPrintedLabel({ ...common, sodiumUnit: "g" }).per100.sodium,
  ).toBe(1000);
});

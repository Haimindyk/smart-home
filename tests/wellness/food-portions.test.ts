import { expect, it } from "vitest";
import { foodSchema, emptyNutrients } from "../../src/lib/health/model";
import { foodPickerItem, productPortion } from "../../src/lib/health/food-portions";
const product = () => foodSchema.parse({ id: "tortilla-product-a", name: "טורטייה מוצר א", basis: "g", source: "label", sourceId: "package-a", per100: { ...emptyNutrients(), kcal: 300 }, unitWeight: { low: 50, high: 60 } });

it("keeps an approved product range, count and nutrition source without scaling other foods", () => {
  const food = product();
  const result = productPortion(food, 2);
  expect(result.quantity).toBe(110);
  expect(result.quantityRange).toEqual({ low: 100, high: 120 });
  expect(result.food.per100.kcal).toBe(300);
  expect(result.food.sourceId).toBe("package-a");
  expect(food.unitWeight).toEqual({ low: 50, high: 60 });
  expect(foodPickerItem(food).quantityRange).toEqual({ low: 50, high: 60 });
});

it("does not claim an approved weight or nutrition source for another tortilla", () => {
  const food = foodSchema.parse({ ...product(), id: "another-product", unitWeight: undefined, source: "ai" });
  expect(() => productPortion(food)).toThrow();
  expect(foodPickerItem(food).quantity).toBe(100);
  expect(foodPickerItem(food).quantityRange).toBeUndefined();
  expect(foodPickerItem(food).food.source).toBe("ai");
});

it("rejects reversed/nonfinite weights and invalid scaled portions, and preserves ml", () => {
  for (const unitWeight of [{ low: 60, high: 50 }, { low: 0, high: 10 }, { low: 50, high: Infinity }])
    expect(foodSchema.safeParse({ ...product(), unitWeight }).success).toBe(false);
  for (const units of [0, -1, NaN, Infinity, 1001, 200])
    expect(() => productPortion(product(), units)).toThrow();
  const drink = { ...product(), basis: "ml" as const };
  expect(productPortion(drink).food.basis).toBe("ml");
});

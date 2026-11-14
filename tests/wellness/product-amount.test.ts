import { expect, it } from "vitest";
import { foodSchema } from "../../src/lib/health/model";
import { productAmount, productAmountItem } from "../../src/lib/health/product-amount";
const food = foodSchema.parse({ id: "off:12345678", barcode: "12345678", name: "Test bar", basis: "g", source: "openfoodfacts", sourceId: "source-reference", per100: { kcal: 250, protein: 10, carbs: 30, fat: 10 } });

it("adds actual grams or weighed units without altering per100/source values", () => {
  const grams = productAmountItem(food, { mode: "amount", quantity: "65", unitAmount: "" });
  expect(grams.quantity).toBe(65);
  const units = productAmountItem(food, { mode: "units", quantity: "2", unitAmount: "30" });
  expect(units.quantity).toBe(60);
  expect(units.food.sourceId).toBe(food.sourceId);
  expect(units.food.per100).toEqual(food.per100);
  expect(units.food.unitWeight).toEqual({ low: 30, high: 30 });
  expect(units.quantity * units.food.per100.kcal / 100).toBe(150);
});

it("never treats unknown units or a manufacturer's serving as a known unit weight", () => {
  expect(() => productAmount({ ...food, servingSize: 30 }, { mode: "units", quantity: "1", unitAmount: "" })).toThrow("unit_amount_required");
});

it("preserves confirmed weight uncertainty and fractional unit counts", () => {
  const result = productAmount({ ...food, unitWeight: { low: 50, high: 60 } }, { mode: "units", quantity: "1,5", unitAmount: "" });
  expect(result.quantity).toBe(82.5);
  expect(result.quantityRange).toEqual({ low: 75, high: 90 });
  expect(() => productAmount({ ...food, unitWeight: { low: 50, high: 60 } }, { mode: "units", quantity: "1", unitAmount: "", unitEdited: true })).toThrow("unit_amount_required");
});

it("keeps liquid units in ml without a mass conversion", () => {
  const result = productAmount({ ...food, basis: "ml" }, { mode: "units", quantity: "2", unitAmount: "250" });
  expect(result.quantity).toBe(500);
  expect(result.food.basis).toBe("ml");
});

it("rejects missing, zero, nonfinite and overflowing amounts", () => {
  for (const quantity of ["", "0", "-2", "NaN", "Infinity", "10001"])
    expect(() => productAmount(food, { mode: "amount", quantity, unitAmount: "" })).toThrow();
  expect(() => productAmount(food, { mode: "units", quantity: "1000", unitAmount: "30" })).toThrow();
});

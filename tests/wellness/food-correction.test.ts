import { describe, it, expect } from "vitest";
import {
  applyFoodCorrection,
  correctionContext,
} from "../../supabase/functions/_shared/wellness-food-correction";
const per100 = {
  kcal: 120,
  protein: 20,
  carbs: 0,
  fat: 4,
  fiber: null,
  sugar: null,
  saturatedFat: null,
  sodium: null,
};
const chicken = {
  id: "chicken",
  quantity: 180,
  food: {
    id: "db-chicken",
    name: "חזה עוף",
    basis: "g",
    source: "usda",
    sourceId: "123",
    per100,
  },
};
const rice = {
  id: "rice",
  quantity: 100,
  food: { id: "rice", name: "אורז", basis: "g", source: "manual", per100 },
};
const change = {
  itemRef: "i0",
  name: "דג",
  per100,
  newQuantity: null,
  assumption: "סוג דג כללי",
};
describe("saved meal correction", () => {
  it("changes food identity while preserving portion and unrelated foods", () => {
    const result = applyFoodCorrection(
      { changes: [change] },
      [chicken, rice],
      "זה דג ולא חזה עוף",
    );
    expect(result[0].quantity).toBe(180);
    expect(result[0].food).toMatchObject({ name: "דג", source: "ai" });
    expect(result[0].food).not.toHaveProperty("sourceId");
    expect(result[1]).toEqual(rice);
  });
  it("does not expose private row IDs or protected manual items", () => {
    const context = correctionContext([chicken, rice]);
    expect(context).toHaveLength(1);
    expect(context[0].itemRef).toBe("i0");
    expect(JSON.stringify(context)).not.toContain("db-chicken");
  });
  it("rejects changes to a protected ingredient or duplicate refs", () => {
    expect(() =>
      applyFoodCorrection(
        { changes: [{ ...change, itemRef: "i1" }] },
        [chicken, rice],
        "דג",
      ),
    ).toThrow();
    expect(() =>
      applyFoodCorrection({ changes: [change, change] }, [chicken], "דג"),
    ).toThrow();
  });
  it("requires an explicit measured amount before changing a portion", () => {
    expect(() =>
      applyFoodCorrection(
        { changes: [{ ...change, newQuantity: 200 }] },
        [chicken],
        "זה דג",
      ),
    ).toThrow();
    expect(
      applyFoodCorrection(
        { changes: [{ ...change, newQuantity: 200 }] },
        [chicken],
        "זה דג 200 גרם",
      )[0].quantity,
    ).toBe(200);
  });
});

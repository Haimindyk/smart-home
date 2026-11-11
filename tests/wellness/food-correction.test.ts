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

const mayonnaise = {
  mentionedText: "מיונז",
  name: "מיונז",
  basis: "g",
  quantity: 15,
  quantityLow: 15,
  quantityHigh: 15,
  per100: { ...per100, kcal: 680, protein: 1, carbs: 1, fat: 74 },
  assumption: "כמות לפי התיקון של המשתמש",
};
it("adds an explicitly mentioned missing condiment while preserving existing foods", () => {
  const result = applyFoodCorrection(
    { changes: [], additions: [mayonnaise] },
    [chicken, rice],
    "יש גם מיונז 15 גרם",
  );
  expect(result).toHaveLength(3);
  expect(result[0]).toEqual(chicken);
  expect(result[1]).toEqual(rice);
  expect(result[2]).toMatchObject({
    quantity: 15,
    quantityRange: { low: 15, high: 15 },
    food: { name: "מיונז", source: "ai", basis: "g" },
  });
  expect(result[2].food).not.toHaveProperty("sourceId");
});
it("does not invent a missing sauce during a portion-only correction or a negated ingredient", () => {
  expect(() =>
    applyFoodCorrection(
      { changes: [], additions: [mayonnaise] },
      [chicken],
      "העוף 110 גרם",
    ),
  ).toThrow("invalid_output");
  expect(() =>
    applyFoodCorrection(
      { changes: [], additions: [mayonnaise] },
      [chicken],
      "תוסיף חסה בלי מיונז",
    ),
  ).toThrow("invalid_output");
  expect(() =>
    applyFoodCorrection(
      { changes: [], additions: [mayonnaise] },
      [chicken],
      "לא חסר מיונז",
    ),
  ).toThrow("invalid_output");
  expect(() =>
    applyFoodCorrection(
      { changes: [], additions: [mayonnaise] },
      [chicken],
      "תוסיף טחינה",
    ),
  ).toThrow("invalid_output");
  expect(() =>
    applyFoodCorrection(
      { changes: [], additions: [mayonnaise] },
      [rice],
      "יש גם מיונז 15 גרם",
    ),
  ).toThrow("invalid_output");
});
it("keeps addition amounts visibly estimated when the user does not know a weight", () => {
  const result = applyFoodCorrection(
    {
      changes: [],
      additions: [{ ...mayonnaise, quantityLow: 5, quantityHigh: 25 }],
    },
    [chicken],
    "יש גם מיונז",
  );
  expect(result[1]).toMatchObject({
    quantity: 15,
    quantityRange: { low: 5, high: 25 },
  });
  expect(() =>
    applyFoodCorrection(
      { changes: [], additions: [{ ...mayonnaise, quantityLow: 30 }] },
      [chicken],
      "יש גם מיונז",
    ),
  ).toThrow("invalid_output");
});

it("preserves the amount and unit explicitly supplied for an added food", () => {
  for (const patch of [
    { quantity: 30, quantityLow: 30, quantityHigh: 30 },
    { basis: "ml" },
    { quantityLow: 5, quantityHigh: 25 },
  ])
    expect(() =>
      applyFoodCorrection(
        { changes: [], additions: [{ ...mayonnaise, ...patch }] },
        [chicken],
        "יש גם מיונז 15 גרם",
      ),
    ).toThrow("invalid_output");
  expect(
    applyFoodCorrection(
      { changes: [], additions: [mayonnaise] },
      [chicken],
      "הוסף 15 גרם מיונז",
    )[1].quantity,
  ).toBe(15);
});

it("changes a portion without replacing the existing nutrient data or provenance", () => {
  const result = applyFoodCorrection(
    {
      changes: [
        {
          ...change,
          name: chicken.food.name,
          newQuantity: 110,
          per100: { ...per100, kcal: 999 },
        },
      ],
    },
    [chicken, rice],
    "חזה עוף 110 גרם",
  );
  expect(result[0].quantity).toBe(110);
  expect(result[0].food).toEqual(chicken.food);
  expect(result[1]).toEqual(rice);
});

it("accepts a concise ingredient correction but rejects an explicitly absent ingredient", () => {
  expect(
    applyFoodCorrection(
      { changes: [], additions: [mayonnaise] },
      [chicken],
      "מיונז 15 גרם",
    ),
  ).toHaveLength(2);
  expect(() =>
    applyFoodCorrection(
      { changes: [], additions: [mayonnaise] },
      [chicken],
      "מיונז לא היה שם",
    ),
  ).toThrow("invalid_output");
});

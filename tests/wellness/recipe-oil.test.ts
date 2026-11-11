import { expect, it } from "vitest";
import { normalizeCompactMeal, compactMealSchema, recipeAwareMealPrompt } from "../../supabase/functions/_shared/wellness-food";
import live from "./recipe-oil-live.json";
import { removeInferredRecipeOil } from "../../supabase/functions/_shared/recipe-oil";

const food = (included = false) => ({ nameEn: "poached eggs in tomato sauce", nameHe: "ביצים ברוטב עגבניות", certainty: "likely", alternatives: [], basis: "g", portion: [250, 200, 300], per100: [110, 8, 5, 6, 1, null, null, null], cookingFatIncluded: included });
const recipe = (accounting = "separate", dish = "shakshuka") => ({ dish, accounting, oilGrams: [10, 4, 20] });
const context = { visualObservations: "Recognizable shakshuka: eggs in tomato sauce. No oil separately visible." };

it("accounts for recipe oil separately without pretending it was seen or verified", () => {
  const result = normalizeCompactMeal({ foods: [food()], recipeEstimate: recipe(), question: "" }, true, context);
  expect(result.items).toHaveLength(2);
  expect(result.items[0].per100.fat).toBe(6); // Intrinsic fat is not erased.
  expect(result.items[1]).toMatchObject({ quantity: 10, quantityLow: 4, quantityHigh: 20, basis: "g", source: "ai", per100: { kcal: 900, fat: 100 } });
  expect(result.items[1].assumption).toContain("לא זוהה בנפרד בתמונה");
  expect(result.items[1].name).toContain("הערכת מתכון");
  expect(result.needsClarification).toBe(false);
});

it("does not add oil when the prepared dish nutrition already includes it", () => {
  const result = normalizeCompactMeal({ foods: [food(true)], recipeEstimate: recipe("included"), question: "" }, true, context);
  expect(result.items).toHaveLength(1);
  expect(result.items[0].assumption).toContain("לא נוסף בנפרד");
});

it("rejects oil declared included when the declared total fat cannot contain it", () => {
  expect(() => normalizeCompactMeal({ foods: [{ ...food(true), per100: [35, 1.9, 7.3, .2, null, null, null, null] }], recipeEstimate: recipe("included") }, true, context)).toThrow("recipe_oil_exceeds_included_fat");
});

it("rejects declared double counting, absent accounting, exact guesses and reversed bounds", () => {
  for (const raw of [
    { foods: [food(true)], recipeEstimate: recipe() },
    { foods: [food()], recipeEstimate: recipe("included") },
    { foods: [{ ...food(), cookingFatIncluded: undefined }], recipeEstimate: recipe() },
    { foods: [food(), { ...food(), nameEn: "olive oil", nameHe: "שמן זית" }], recipeEstimate: recipe() },
    { foods: [food()], recipeEstimate: { ...recipe(), oilGrams: [10, 10, 10] } },
    { foods: [food()], recipeEstimate: { ...recipe(), oilGrams: [10, 20, 4] } },
  ]) expect(() => normalizeCompactMeal(raw, true, context)).toThrow();
});

it("never overrides oil-free preparation, measured oil amounts or a rejected dish identity", () => {
  for (const description of ["שקשוקה ללא שמן", "shakshuka without added oil", "שקשוקה עם 7 גרם שמן", "10 g olive oil in shakshuka", "זה לא שקשוקה"]) {
    expect(() => normalizeCompactMeal({ foods: [food()], recipeEstimate: recipe() }, true, { ...context, description })).toThrow("recipe_conflicts_with_user");
  }
});

it("requires named recipe evidence and supports Moroccan fish without inferring hidden mayonnaise", () => {
  expect(() => normalizeCompactMeal({ foods: [food()], recipeEstimate: recipe() }, true, { visualObservations: "eggs on toast" })).toThrow("unsupported_recipe_estimate");
  expect(() => normalizeCompactMeal({ foods: [food()], recipeEstimate: recipe("separate", "sandwich") }, true, context)).toThrow("unsupported_recipe_estimate");
  const result = normalizeCompactMeal({ foods: [food()], recipeEstimate: recipe("separate", "moroccan_fish") }, true, { description: "דג מרוקאי" });
  expect(result.items[1].assumption).toContain("דג מרוקאי");
  expect(result.items.some((i) => /מיונז/.test(i.name))).toBe(false);
});

it("keeps legacy/non-recipe estimates unchanged and makes the new contract explicit", () => {
  expect(normalizeCompactMeal({ foods: [food()], recipeEstimate: null }, true).items).toHaveLength(1);
  expect(compactMealSchema().required).toContain("recipeEstimate");
  expect(recipeAwareMealPrompt).toContain("NOT the entire cooking pot");
});

it("accepts actual hosted recipe outputs without asking before automatic save", () => {
  for (const sample of live.cases) {
    const result = normalizeCompactMeal(sample.output, true, sample);
    expect(result.items.at(-1)?.name).toBe("שמן בישול — הערכת מתכון");
    expect(result.items.at(-1)?.quantity).toBe(sample.output.recipeEstimate.oilGrams[0]);
    expect(result.question).toBe("");
  }
});

it("removes only the inferred oil on an explicit no-oil correction, preserving sources and other foods", () => {
  const other = { id: "fish", food: { name: "דג", source: "ai" }, quantity: 150 };
  const oil = { id: "oil", food: { name: "שמן בישול — הערכת מתכון", source: "ai" }, quantity: 10, assumption: "הערכת מתכון לשקשוקה: שמן משוער" };
  expect(removeInferredRecipeOil([other, oil], "לא היה שמן")).toEqual([other]);
  expect(removeInferredRecipeOil([other, { ...oil, food: { ...oil.food, source: "label" } }], "בלי שמן")).toBeNull();
  expect(removeInferredRecipeOil([other, oil], "היו 5 גרם שמן")).toBeNull();
  expect(removeInferredRecipeOil([oil], "ללא שמן")).toBeNull();
});

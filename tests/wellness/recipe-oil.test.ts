import { expect, it } from "vitest";
import { normalizeCompactMeal, compactMealSchema, recipeAwareMealPrompt } from "../../supabase/functions/_shared/wellness-food";
import live from "./recipe-oil-live.json";
import preparationLive from "./preparation-oil-live.json";
import { removeInferredRecipeOil } from "../../supabase/functions/_shared/recipe-oil";

const food = (included = false) => ({ nameEn: "poached eggs in tomato sauce", nameHe: "ביצים ברוטב עגבניות", certainty: "likely", alternatives: [], basis: "g", portion: [250, 200, 300], per100: [110, 8, 5, 6, 1, null, null, null], cookingFatIncluded: included });
const recipe = (accounting = "separate", dish = "שקשוקה", evidence = "shakshuka", method = "stewed") => ({ dish, method, evidence, rationale: "אופן ההכנה המקובל עשוי לכלול שמן", accounting, oilGrams: [10, 4, 20] });
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

it("requires quoted preparation evidence but does not restrict dish identities", () => {
  expect(() => normalizeCompactMeal({ foods: [food()], recipeEstimate: recipe() }, true, { visualObservations: "eggs on toast" })).toThrow("unsupported_recipe_estimate");
  const result = normalizeCompactMeal({ foods: [food()], recipeEstimate: recipe("separate", "דג מרוקאי", "דג מרוקאי") }, true, { description: "דג מרוקאי" });
  expect(result.items[1].assumption).toContain("דג מרוקאי");
  expect(result.items.some((i) => /מיונז/.test(i.name))).toBe(false);
});

it("keeps legacy/non-recipe estimates unchanged and makes the new contract explicit", () => {
  expect(normalizeCompactMeal({ foods: [food()], recipeEstimate: null }, true).items).toHaveLength(1);
  expect(compactMealSchema().required).toContain("recipeEstimate");
  expect(recipeAwareMealPrompt).toContain("NOT the entire cooking pot");
});

it("keeps archived v3 probes visibly distinct from the generalized contract", () => {
  for (const sample of live.cases) {
    expect(() => normalizeCompactMeal(sample.output, true, sample)).toThrow();
  }
});

it("supports unrelated cuisines and cooking methods without adding named dishes to code", () => {
  for (const [dish, evidence, method] of [
    ["טופו מוקפץ", "stir-fried tofu", "stir_fried"],
    ["קציצות ברוטב", "meatballs in tomato stew", "stewed"],
    ["תפוחי אדמה בתנור", "roasted potatoes", "roasted"],
    ["דג במחבת", "pan-fried fish", "pan_fried"],
    ["פטריות בתנור", "פטריות בתנור", "baked"],
  ]) {
    const result = normalizeCompactMeal({ foods: [food()], recipeEstimate: recipe("separate", dish, evidence, method) }, true, { visualObservations: evidence });
    expect(result.items.at(-1)?.assumption).toContain(dish);
    expect(result.items.at(-1)?.quantity).toBe(10);
  }
  expect(recipeAwareMealPrompt).toContain("without a whitelist");
});

it("does not manufacture preparation evidence or add oil to raw/steamed food", () => {
  for (const [dish, evidence] of [["תפוח", "raw apple"], ["ברוקולי", "steamed broccoli"]]) {
    expect(() => normalizeCompactMeal({ foods: [food()], recipeEstimate: recipe("separate", dish, evidence) }, true, { visualObservations: evidence })).toThrow("unsupported_recipe_estimate");
  }
  expect(() => normalizeCompactMeal({ foods: [food()], recipeEstimate: recipe("separate", "טופו", "fried tofu") }, true, { visualObservations: "tofu" })).toThrow("unsupported_recipe_estimate");
  expect(normalizeCompactMeal({ foods: [food()], recipeEstimate: null }, true, { visualObservations: "raw apple" }).items).toHaveLength(1);
});

it("does not reject an actually cooked component because of a nearby fresh side", () => {
  const result = normalizeCompactMeal({ foods: [food()], recipeEstimate: recipe("separate", "טופו מוקפץ", "stir-fried tofu", "stir_fried") }, true, { visualObservations: "fresh salad alongside stir-fried tofu" });
  expect(result.items.at(-1)?.quantity).toBe(10);
});

it("normalizes actual generalized hosted outputs: oil for a stir-fry, none for steamed vegetables", () => {
  const stirFry = normalizeCompactMeal(preparationLive.cases[0].output, true, preparationLive.cases[0]);
  expect(stirFry.items.at(-1)?.name).toBe("שמן בישול — הערכת מתכון");
  expect(stirFry.items.at(-1)?.quantity).toBe(10);
  const steamed = normalizeCompactMeal(preparationLive.cases[1].output, true, preparationLive.cases[1]);
  expect(steamed.items).toHaveLength(1);
  expect(steamed.items.some((i) => i.name.includes("שמן"))).toBe(false);
  expect(stirFry.question).toBe("");
  expect(steamed.question).toBe("");
});

it("removes only the inferred oil on an explicit no-oil correction, preserving sources and other foods", () => {
  const other = { id: "fish", food: { name: "דג", source: "ai" }, quantity: 150 };
  const oil = { id: "oil", food: { name: "שמן בישול — הערכת מתכון", source: "ai" }, quantity: 10, assumption: "הערכת מתכון לשקשוקה: שמן משוער" };
  expect(removeInferredRecipeOil([other, oil], "לא היה שמן")).toEqual([other]);
  expect(removeInferredRecipeOil([other, { ...oil, food: { ...oil.food, source: "label" } }], "בלי שמן")).toBeNull();
  expect(removeInferredRecipeOil([other, oil], "היו 5 גרם שמן")).toBeNull();
  expect(removeInferredRecipeOil([oil], "ללא שמן")).toBeNull();
});

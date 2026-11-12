import { number, parseNutrition, record, text, type NutritionEstimate } from "./wellness-core.ts";

const cookingMethods = ["pan_fried", "deep_fried", "sauteed", "stir_fried", "stewed", "roasted", "baked", "grilled"];
export const recipeOilSchema = { anyOf: [
  { type: "null" },
  { type: "object", additionalProperties: false, properties: {
    dish: { type: "string", minLength: 2, maxLength: 100, pattern: ".*[א-ת].*" },
    method: { type: "string", enum: cookingMethods },
    evidence: { type: "string", minLength: 3, maxLength: 220 },
    rationale: { type: "string", minLength: 3, maxLength: 300, pattern: ".*[א-ת].*" },
    accounting: { type: "string", enum: ["included", "separate"] },
    oilGrams: { type: "array", minItems: 3, maxItems: 3, items: { type: "number", minimum: .1, maximum: 10000 } },
  }, required: ["dish", "method", "evidence", "rationale", "accounting", "oilGrams"] },
] };

export const recipeOilPrompt = `General cooking-fat estimation: consider likely added cooking oil for ANY recognizable prepared dish or identified cooking method, without a whitelist of dish names. This includes cuisines and dishes beyond any examples. Use recipeEstimate only when the dish/preparation reasonably supports added oil, even when oil is not separately visible. Do not add oil to every cooked food. This is a recipe assumption, NEVER a visual observation or measured fact. recipeEstimate is null when preparation is unknown or ambiguous, for raw fruit/vegetables, undressed salads, boiled/steamed foods with no indication of added fat, explicitly oil-free preparation, or explicit user-provided oil amounts (include those directly as normal foods instead). Supply a natural Hebrew dish label, the most plausible supported cooking method, evidence copied VERBATIM from visualObservations or the user description, and a short Hebrew rationale explaining the recipe assumption. The cooking method may be inferred from a confidently identified dish; evidence must still quote the actual observations, not invented details. Decide recipeEstimate BEFORE generating foods and make every cookingFatIncluded flag and nutrient vector consistent with that plan. Otherwise provide dish, accounting and oilGrams=[best estimate,lower,upper] in GRAMS for the portion actually eaten, NOT the entire cooking pot. Do not use a fixed oil amount for all servings. Use a nonzero uncertainty interval. Set cookingFatIncluded on EVERY food. For accounting=separate, every food's per100 must EXCLUDE added cooking oil (retain intrinsic fat in eggs/fish), cookingFatIncluded=false for all, and do NOT emit an oil food: the server adds one estimated oil row. PREFER accounting=separate when returning separate eggs/fish/vegetables. Use accounting=included only for a complete prepared dish or genuinely oil-containing sauce, whose per100 fat mathematically contains the estimated oil: sum(portion_g * fat_per100 / 100) across cookingFatIncluded foods MUST be at least oilGrams[0]. A low-fat plain tomato sauce cannot contain the claimed added oil. For accounting=included, dish/sauce per100 already includes oil: mark those food(s) cookingFatIncluded=true, emit no separate oil food and never duplicate a finished dish plus its components. This exception never permits hidden mayonnaise or other condiments. Explicit user corrections override typical recipes.`;

export function applyRecipeOil(estimate: NutritionEstimate, raw: unknown, context: { visualObservations?: string; description?: string }): NutritionEstimate {
  const r = record(raw);
  if (r.recipeEstimate == null) return estimate;
  const plan = record(r.recipeEstimate);
  const dish = text(plan.dish, 100), evidence = text(plan.evidence, 220), rationale = text(plan.rationale, 300);
  const description = context.description ?? "";
  const normalized = (s: string) => s.toLocaleLowerCase().replace(/\s+/g, " ").trim();
  const observed = normalized(`${context.visualObservations ?? ""}\n${description}`);
  const quote = normalized(evidence), position = observed.indexOf(quote);
  if ((dish.match(/[א-ת]/g)?.length ?? 0) < 2 || evidence.length < 3 ||
      (rationale.match(/[א-ת]/g)?.length ?? 0) < 3 || !cookingMethods.includes(String(plan.method)) || position < 0)
    throw new Error("unsupported_recipe_estimate");
  // Evidence must be a real phrase from the observations/user input, rather
  // than a made-up dish or a raw/steamed food relabelled as fried.
  const nearby = observed.slice(Math.max(0, position - 22), position + quote.length);
  if (/\b(?:raw|fresh|uncooked|boiled|steamed)\b|(?:^|[^א-ת])(?:טרי(?:ה|ים|ות)?|לא מבושל|מבושל במים|מאודה)(?=$|[^א-ת])/.test(nearby) &&
      !/\b(?:fried|sauteed|sautéed|roasted|grilled|baked|stewed)\b|מטוג|מוקפ|צלוי|אפוי|תבשיל/.test(quote))
    throw new Error("unsupported_recipe_estimate");
  if (/ללא\s+(?:תוספת\s+)?שמן|בלי\s+שמן|\b(?:no|without)\s+(?:added\s+)?oil\b|\boil[- ]free\b/i.test(description))
    throw new Error("recipe_conflicts_with_user");
  if ([normalized(dish), quote].some((identity) => ["לא ", "not ", "not a "].some((negation) => normalized(description).includes(negation + identity))) ||
      /\d+(?:[.,]\d+)?\s*(?:גרם|ג[׳']|g\b|ml\b|מ[״"]?ל)\s*(?:(?:olive|cooking|vegetable)\s+)?(?:שמן|oil)|(?:שמן(?:\s+זית)?|oil)\s*[:=]?\s*\d+\s*(?:גרם|g\b|ml\b)/i.test(description))
    throw new Error("recipe_conflicts_with_user");
  if (!Array.isArray(plan.oilGrams) || plan.oilGrams.length !== 3)
    throw new Error("invalid_recipe_estimate");
  const [quantity, quantityLow, quantityHigh] = plan.oilGrams.map((v) => number(v, .1, 10000));
  if (quantityLow > quantity || quantityHigh < quantity || quantityLow === quantityHigh || !Array.isArray(r.foods) || !estimate.items.length)
    throw new Error("invalid_recipe_estimate");
  const foods = r.foods.map(record);
  if (foods.some((f) => typeof f.cookingFatIncluded !== "boolean"))
    throw new Error("missing_cooking_fat_accounting");
  const includesFat = foods.some((f) => f.per100 != null && f.cookingFatIncluded === true);
  const hasOil = estimate.items.some((i) => /^שמן(?:\s|$)|\boil\b/i.test(i.name)) || foods.some((f) => /\boil\b/i.test(String(f.nameEn)));
  // Refuse contradictory accounting instead of adding fat twice or attempting
  // to subtract an unknown amount of oil from a nutritional record.
  if (hasOil || (plan.accounting === "separate" && includesFat) || (plan.accounting === "included" && !includesFat) || !["included", "separate"].includes(String(plan.accounting)))
    throw new Error("duplicate_or_ambiguous_cooking_fat");
  if (plan.accounting === "included") {
    const includedFat = foods.filter((f) => f.cookingFatIncluded === true && f.per100 != null).reduce((total, f) => {
      if (!Array.isArray(f.per100) || !Array.isArray(f.portion) || f.basis !== "g") throw new Error("invalid_recipe_estimate");
      return total + number(f.portion[0], .1, 10000) * number(f.per100[3], 0, 1000) / 100;
    }, 0);
    if (includedFat + .01 < quantity) throw new Error("recipe_oil_exceeds_included_fat");
  }
  const prefix = `הערכת מתכון ל${dish}: `;
  const items = estimate.items.map((i) => ({ ...i, assumption: prefix + (plan.accounting === "included"
    ? "שמן הבישול כלול בערכי המנה או הרוטב ולא נוסף בנפרד. "
    : "ערכי הרכיבים אינם כוללים שמן בישול נוסף; השמן מחושב בשורה נפרדת. ") + i.assumption }));
  if (plan.accounting === "separate") items.push({
    name: "שמן בישול — הערכת מתכון", basis: "g", quantity, quantityLow, quantityHigh, source: "ai",
    // Generic fat energy factor, not an oil brand or verified database value.
    per100: { kcal: 900, protein: 0, carbs: 0, fat: 100, fiber: null, sugar: null, saturatedFat: null, sodium: null },
    assumption: prefix + `שמן משוער למנה שנאכלה, לא זוהה בנפרד בתמונה. ${rationale}. טווח ${quantityLow}–${quantityHigh} גרם; כ־9 קלוריות לגרם שומן. ניתן לתקן לפי המתכון שלך.`,
  });
  return parseNutrition({ ...estimate, items });
}

// A same-name catalog replacement could contain cooking fat excluded by the
// decomposed recipe. Keep this estimate's nutritional accounting together.
export function hasRecipeOilEstimate(raw: unknown) {
  return record(raw).recipeEstimate != null;
}

export function removeInferredRecipeOil(items: unknown[], correction: string) {
  // Only this exact preparation correction and the explicitly inferred AI row.
  // A combined request still goes through the normal correction flow.
  if (!/^(?:לא היה שמן|ללא שמן|בלי שמן|no oil|without oil)[.!\s]*$/i.test(correction.trim())) return null;
  const remaining = items.filter((raw) => {
    const item = record(raw), food = record(item.food);
    return !(food.source === "ai" && food.name === "שמן בישול — הערכת מתכון" && String(item.assumption).startsWith("הערכת מתכון ל"));
  });
  if (!remaining.length || remaining.length === items.length) return null;
  return remaining.map((raw) => {
    const item = record(raw);
    const assumption = String(item.assumption ?? "");
    const updated = assumption.replace(/^הערכת מתכון ל[^:]+: ערכי הרכיבים אינם כוללים שמן בישול נוסף; השמן מחושב בשורה נפרדת\. /, "לפי התיקון שלך, ללא שמן בישול נוסף. ");
    return updated === assumption ? raw : { ...item, assumption: updated };
  });
}

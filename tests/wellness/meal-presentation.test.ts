import { expect, it } from "vitest";
import {
  mealTitle,
  displayedMealTitle,
} from "../../src/lib/health/meal-presentation";
import { type MealItem } from "../../src/lib/health/model";
const meal = (names: string[]) =>
  names.map((name) => ({ food: { name } })) as MealItem[];
it("names meals using detected foods without inventing a dish or repeating ingredients", () => {
  expect(mealTitle(meal(["דג אפוי", "אורז", "סלט", "אורז"]))).toBe(
    "דג אפוי, אורז וסלט",
  );
  expect(mealTitle(meal(["פסטה"]))).toBe("פסטה");
  expect(mealTitle(meal(["טופו", "טופו"]))).toBe("טופו");
  expect(mealTitle(meal([]))).toBe("");
});

it("repairs generic legacy photo headings for display while preserving custom titles", () => {
  const data = {
    name: "ארוחה מצולמת",
    items: meal(["דג אפוי"]),
    aiEstimate: {},
  };
  expect(displayedMealTitle(data)).toBe("דג אפוי");
  expect(displayedMealTitle({ ...data, name: "ארוחת הצהריים שלי" })).toBe(
    "ארוחת הצהריים שלי",
  );
  expect(displayedMealTitle({ ...data, aiEstimate: undefined })).toBe(
    "ארוחה מצולמת",
  );
});

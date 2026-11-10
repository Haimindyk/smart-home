import type { MealItem } from "./model";

/** A title drawn only from detected foods, without a second model request. */
export function mealTitle(items: MealItem[]) {
  const names = [
    ...new Set(items.map((i) => i.food.name.trim()).filter(Boolean)),
  ].slice(0, 3);
  return (
    names.length < 2
      ? (names[0] ?? "")
      : `${names.slice(0, -1).join(", ")} ו${names.at(-1)}`
  ).slice(0, 160);
}

export function isAutomaticMealTitle(meal: {
  name: string;
  items: MealItem[];
  aiEstimate?: unknown;
}) {
  return (
    !!meal.aiEstimate &&
    (["ארוחה מצולמת", "Photo meal"].includes(meal.name) ||
      meal.name === mealTitle(meal.items))
  );
}
export function displayedMealTitle(
  meal: { name: string; items: MealItem[]; aiEstimate?: unknown },
  fallback = "",
) {
  return isAutomaticMealTitle(meal)
    ? mealTitle(meal.items) || fallback
    : meal.name || fallback;
}

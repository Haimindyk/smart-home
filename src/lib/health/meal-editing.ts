"use client";
import { useHealthStore } from "./store";
import { type HealthRow, type MealItem, payloadSchemas } from "./model";
import { isAutomaticMealTitle, mealTitle } from "./meal-presentation";

export function editedMealData(row: HealthRow<"meals">, items: MealItem[]) {
  if (new Set(items.map((i) => i.id)).size !== items.length) throw new Error("invalid_input");
  return payloadSchemas.meals.parse({
    ...row.data,
    items,
    name: isAutomaticMealTitle(row.data) ? mealTitle(items) : row.data.name,
  });
}

export async function saveMealItems(row: HealthRow<"meals">, items: MealItem[]) {
  const state = useHealthStore.getState();
  const current = state.data.meals.find((m) => m.id === row.id);
  if (!state.owner || row.owner_user_id !== state.owner || (current && current.owner_user_id !== state.owner)) throw new Error("session_mismatch");
  if (!current || current.version !== row.version) throw new Error("version_conflict");
  const data = editedMealData(current, items);
  // Existing offline queue/expectedVersion handling remains authoritative.
  try { return await state.save("meals", data, current); }
  catch (error) {
    // A cache write can fail AFTER an edit has entered the durable queue/local
    // store. Recognize that exact accepted edit instead of inviting a duplicate.
    const latest = useHealthStore.getState();
    const accepted = latest.data.meals.find((m) => m.id === row.id);
    if (latest.owner === row.owner_user_id && accepted?.owner_user_id === row.owner_user_id &&
        accepted.version === row.version + 1 && JSON.stringify(accepted.data) === JSON.stringify(data)) return accepted;
    throw error;
  }
}

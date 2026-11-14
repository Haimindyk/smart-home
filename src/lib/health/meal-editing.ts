"use client";
import { useHealthStore } from "./store";
import { type HealthRow, type MealItem, type Payload, payloadSchemas } from "./model";
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
  return saveMealData(row, editedMealData(row, items));
}

export async function saveMealFavorite(row: HealthRow<"meals">, favorite: boolean) {
  return saveMealData(row, payloadSchemas.meals.parse({ ...row.data, favorite }));
}

async function saveMealData(row: HealthRow<"meals">, data: Payload<"meals">) {
  const state = useHealthStore.getState();
  const current = state.data.meals.find((m) => m.id === row.id);
  if (!state.owner || row.owner_user_id !== state.owner || (current && current.owner_user_id !== state.owner)) throw new Error("session_mismatch");
  if (!current || current.version !== row.version) throw new Error("version_conflict");
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

export function repeatedMealData(row: HealthRow<"meals">, date: string) {
  // A new meal has its own item IDs. Keep source values/units and assumptions,
  // but never attach another entry's image or AI correction identity.
  return payloadSchemas.meals.parse({
    date, kind: row.data.kind, name: isAutomaticMealTitle(row.data) || !row.data.name.trim() ? mealTitle(row.data.items) : row.data.name,
    items: row.data.items.map((item) => ({ ...item, id: crypto.randomUUID() })),
    imagePath: null,
  });
}

export async function saveRepeatedMeal(row: HealthRow<"meals">, data: ReturnType<typeof repeatedMealData>, id: string) {
  const state = useHealthStore.getState();
  if (!state.owner || row.owner_user_id !== state.owner) throw new Error("session_mismatch");
  const sameEntry = (candidate: HealthRow<"meals"> | undefined) => candidate?.owner_user_id === row.owner_user_id && JSON.stringify(candidate.data) === JSON.stringify(data);
  const accepted = state.data.meals.find((m) => m.id === id);
  if (accepted) {
    if (sameEntry(accepted)) return accepted;
    throw new Error("version_conflict");
  }
  const source = state.data.meals.find((m) => m.id === row.id);
  if (!source || source.version !== row.version) throw new Error("version_conflict");
  if (source.owner_user_id !== state.owner) throw new Error("session_mismatch");
  try { return await state.save("meals", data, undefined, id); }
  catch (error) {
    const latest = useHealthStore.getState();
    const saved = latest.data.meals.find((m) => m.id === id);
    if (latest.owner === row.owner_user_id && sameEntry(saved)) return saved!;
    throw error;
  }
}

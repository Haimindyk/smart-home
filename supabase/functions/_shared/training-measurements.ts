type Item = { id: string; food: { name: string; basis: string; per100: unknown; source: string }; quantity: number };

/** Weighed labels require explicit grams for every ingredient; never infer density. */
export function nutritionTrainingItems(items: Item[], weighed: boolean, measurements?: unknown) {
  const weights = new Map<string, number>();
  if (weighed) {
    if (!items.length || items.length > 100 || items.some((i) => i.food.basis !== "g") ||
      !Array.isArray(measurements) || measurements.length !== items.length)
      throw new Error("training_weights_required");
    for (const entry of measurements) {
      if (!entry || typeof entry !== "object" || Array.isArray(entry) ||
        typeof entry.itemId !== "string" || weights.has(entry.itemId) ||
        !items.some((i) => i.id === entry.itemId) || typeof entry.grams !== "number" ||
        !Number.isFinite(entry.grams) || entry.grams <= 0 || entry.grams > 10000)
        throw new Error("training_weights_required");
      weights.set(entry.itemId, entry.grams);
    }
    if (items.some((i) => !weights.has(i.id))) throw new Error("training_weights_required");
  }
  return items.map((i) => ({
    name: i.food.name, basis: i.food.basis, per100: i.food.per100,
    quantity: weighed ? weights.get(i.id)! : i.quantity, source: i.food.source,
  }));
}

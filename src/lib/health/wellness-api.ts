"use client";
import { mealTitle, isAutomaticMealTitle } from "./meal-presentation";
import { healthFunction } from "./api";
import { useHealthStore } from "./store";
import { mealItemSchema, type HealthRow } from "./model";
import {
  parseNutrition,
  type NutritionEstimate,
  type CoachProposal,
  type TrainingPreferences,
} from "../../../supabase/functions/_shared/wellness-core";
export type { CoachProposal, TrainingPreferences };
export async function wellnessRequest<T>(
  input: Record<string, unknown>,
): Promise<T> {
  const owner = useHealthStore.getState().owner;
  if (!owner) throw new Error("session_required");
  if (!navigator.onLine) throw new Error("online_required");
  const result = await healthFunction<T>("wellness-ai", input, owner);
  if (useHealthStore.getState().owner !== owner)
    throw new Error("session_mismatch");
  return result;
}
export async function estimateMeal(input: {
  requestId: string;
  mode: "text" | "meal";
  description: string;
  imagePath?: string;
  automatic?: boolean;
}) {
  const response = await wellnessRequest<
    NutritionEstimate & { analysisId: string }
  >({ action: "nutrition", ...input });
  const estimate = parseNutrition(response);
  return {
    ...estimate,
    items: estimate.items.map((i, index) =>
      mealItemSchema.parse({
        id: crypto.randomUUID(),
        food: {
          id: response.items[index].sourceId ?? crypto.randomUUID(),
          name: i.name,
          basis: i.basis,
          per100: i.per100,
          source: response.items[index].source ?? "ai",
          sourceId: response.items[index].sourceId,
        },
        quantity: i.quantity,
        quantityRange: { low: i.quantityLow, high: i.quantityHigh },
        assumption: i.assumption,
      }),
    ),
  };
}

// Two views of one plate become a single image; never sum two independent analyses.
export async function combineMealPhotos(
  first: File,
  second: File,
): Promise<File> {
  const load = async (file: File) => {
    if (!file.type.startsWith("image/") || file.size > 25 * 1024 * 1024)
      throw new Error("invalid_image");
    const bitmap = await createImageBitmap(file);
    return bitmap;
  };
  const a = await load(first);
  let b: ImageBitmap | undefined;
  try {
    b = await load(second);
    const canvas = document.createElement("canvas");
    canvas.width = 1536;
    canvas.height = 800;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("invalid_image");
    ctx.fillStyle = "white";
    ctx.fillRect(0, 0, 1536, 800);
    for (const [i, img] of [a, b].entries()) {
      const scale = Math.min(768 / img.width, 750 / img.height);
      ctx.drawImage(
        img,
        i * 768 + (768 - img.width * scale) / 2,
        40 + (750 - img.height * scale) / 2,
        img.width * scale,
        img.height * scale,
      );
      ctx.fillStyle = "black";
      ctx.font = "24px sans-serif";
      ctx.fillText(
        i === 0 ? "A: same meal, top view" : "B: same meal, side view",
        i * 768 + 12,
        28,
      );
    }
    const blob = await new Promise<Blob>((resolve, reject) =>
      canvas.toBlob(
        (b) => (b ? resolve(b) : reject(new Error("invalid_image"))),
        "image/jpeg",
        0.85,
      ),
    );
    return new File([blob], "meal-two-views.jpg", { type: "image/jpeg" });
  } finally {
    a.close();
    b?.close();
  }
}

export async function correctSavedMeal(
  row: HealthRow<"meals">,
  description: string,
  requestId: string,
) {
  const owner = useHealthStore.getState().owner;
  if (!owner || row.owner_user_id !== owner)
    throw new Error("session_mismatch");
  const current = useHealthStore
    .getState()
    .data.meals.find((m) => m.id === row.id);
  if (current?.data.aiEstimate?.lastCorrectionId === requestId) return current;
  if (!current || current.version !== row.version)
    throw new Error("version_conflict");
  if (useHealthStore.getState().pending) throw new Error("sync_required");
  const response = await wellnessRequest<{
    items: unknown[];
    expectedVersion: number;
    mealId: string;
  }>({
    action: "correct_meal",
    mealId: row.id,
    expectedVersion: row.version,
    description,
    requestId,
  });
  const latest = useHealthStore
    .getState()
    .data.meals.find((m) => m.id === row.id);
  if (useHealthStore.getState().owner !== owner)
    throw new Error("session_mismatch");
  if (
    !latest ||
    response.mealId !== row.id ||
    latest.version !== response.expectedVersion
  )
    throw new Error("version_conflict");
  const items = response.items.map((i) => mealItemSchema.parse(i));
  return useHealthStore.getState().save(
    "meals",
    {
      ...latest.data,
      name: isAutomaticMealTitle(latest.data)
        ? mealTitle(items)
        : latest.data.name,
      items,
      aiEstimate: {
        analysisId: latest.data.aiEstimate?.analysisId ?? requestId,
        lastCorrectionId: requestId,
      },
    },
    latest,
  );
}

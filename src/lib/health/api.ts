import { createClient } from "@/lib/supabase/client";
import { foodSchema, mealItemSchema, type Food, type MealItem } from "./model";
import { z } from "zod";
export async function healthFunction<T>(
  name: string,
  body: Record<string, unknown>,
): Promise<T> {
  const c = createClient();
  const {
    data: { session },
  } = await c.auth.getSession();
  if (!session) throw new Error("session_required");
  const { data, error } = await c.functions.invoke(name, {
    body,
    headers: { Authorization: `Bearer ${session.access_token}` },
  });
  if (error) {
    let code = "request_failed";
    try {
      const details = await error.context?.json();
      code = details?.error ?? code;
    } catch {
      /* A transport failure may not have a JSON body. */
    }
    throw new Error(code);
  }
  if (data?.error) throw new Error(data.error);
  return data as T;
}
export async function lookupFood(query: string, barcode?: string) {
  const data = await healthFunction<{
    foods: unknown[];
    name?: string;
    needsLabel?: boolean;
  }>("food-lookup", { query, barcode });
  return { ...data, foods: z.array(foodSchema).parse(data.foods) };
}
export async function prepareImage(file: File): Promise<Blob> {
  if (!file.type.startsWith("image/") || file.size > 25 * 1024 * 1024)
    throw new Error("invalid_image");
  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    image.src = url;
    await image.decode();
    const scale = Math.min(
      1,
      1800 / Math.max(image.naturalWidth, image.naturalHeight),
    );
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(image.naturalWidth * scale);
    canvas.height = Math.round(image.naturalHeight * scale);
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("invalid_image");
    ctx.fillStyle = "white";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(image, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise<Blob>((resolve, reject) =>
      canvas.toBlob(
        (b) => (b ? resolve(b) : reject(new Error("invalid_image"))),
        "image/jpeg",
        0.86,
      ),
    );
    if (blob.size > 5242880) throw new Error("invalid_image");
    return blob;
  } finally {
    URL.revokeObjectURL(url);
  }
}
export type Analysis = {
  items: MealItem[];
  needsClarification: boolean;
  question: string;
  analysisId: string;
};
export async function uploadMealImage(file: File, owner: string) {
  const blob = await prepareImage(file);
  const path = `${owner}/${crypto.randomUUID()}.jpg`;
  const { error } = await createClient()
    .storage.from("health-images")
    .upload(path, blob, { contentType: "image/jpeg", upsert: false });
  if (error) throw new Error("upload_failed");
  return path;
}
export async function analyzeMeal(
  path: string,
  requestId: string,
  mode: "meal" | "label",
  description: string,
): Promise<Analysis> {
  const raw = await healthFunction<{
    items: {
      name: string;
      quantity: number;
      basis: "g" | "ml";
      per100: Food["per100"];
      source?: Food["source"];
      sourceId?: string;
      assumption: string;
    }[];
    needsClarification: boolean;
    question: string;
    analysisId: string;
  }>("nutrition-analyze", { imagePath: path, requestId, mode, description });
  const items = raw.items.map((i) =>
    mealItemSchema.parse({
      id: crypto.randomUUID(),
      food: {
        id: crypto.randomUUID(),
        name: i.name,
        basis: i.basis,
        source: i.source ?? (mode === "label" ? "label" : "ai"),
        sourceId: i.sourceId,
        per100: i.per100,
      },
      quantity: i.quantity,
      assumption: i.assumption,
    }),
  );
  return {
    items,
    needsClarification: raw.needsClarification,
    question: raw.question,
    analysisId: raw.analysisId,
  };
}

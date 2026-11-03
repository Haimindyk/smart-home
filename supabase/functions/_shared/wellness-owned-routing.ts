import registry from "./wellness-owned-models.json" with { type: "json" };
import type { Environment } from "./wellness-provider.ts";
export type OwnedTask = "nutrition_text" | "nutrition_photo" | "coach_program";
export type OwnedModel = {
  id: string;
  task: OwnedTask;
  status: "approved";
  synthetic: false;
  weightsSha256: string;
  datasetSha256: string;
  evaluationSha256: string;
  runtimeVerified: true;
  cloudflareModel: string;
  lora: string;
};
const allowed = new Set([
  "@cf/mistral/mistral-7b-instruct-v0.2-lora",
  "@cf/meta/llama-3.2-11b-vision-instruct",
]);
export function ownModel(
  task: OwnedTask,
  env: Environment,
  models: unknown[] = registry.models,
): OwnedModel | null {
  if (env("WELLNESS_MODEL_SOURCE") !== "owned") return null;
  const model = models.find(
    (m: unknown) =>
      !!m &&
      typeof m === "object" &&
      (m as OwnedModel).task === task &&
      (m as OwnedModel).id === env(`WELLNESS_${task.toUpperCase()}_VERSION`),
  ) as OwnedModel | undefined;
  if (
    !model ||
    model.status !== "approved" ||
    model.synthetic !== false ||
    model.runtimeVerified !== true ||
    !allowed.has(model.cloudflareModel) ||
    ![model.weightsSha256, model.datasetSha256, model.evaluationSha256].every(
      (s) => typeof s === "string" && /^[a-f0-9]{64}$/.test(s),
    ) ||
    !/^[a-z0-9][a-z0-9-]{2,63}$/.test(model.lora)
  )
    throw new Error("not_configured");
  if (
    (task === "nutrition_photo") !==
    (model.cloudflareModel === "@cf/meta/llama-3.2-11b-vision-instruct")
  )
    throw new Error("not_configured");
  return model;
}

import { it, expect } from "vitest";
import { ownModel } from "../../supabase/functions/_shared/wellness-owned-routing";
const env = (key: string) =>
  (
    ({
      WELLNESS_MODEL_SOURCE: "owned",
      WELLNESS_NUTRITION_TEXT_VERSION: "meal-v1",
    }) as Record<string, string>
  )[key];
const model = {
  id: "meal-v1",
  task: "nutrition_text",
  status: "approved",
  synthetic: false,
  weightsSha256: "a".repeat(64),
  datasetSha256: "b".repeat(64),
  evaluationSha256: "c".repeat(64),
  runtimeVerified: true,
  cloudflareModel: "@cf/mistral/mistral-7b-instruct-v0.2-lora",
  lora: "wellness-meal-v1",
};
it("does not claim hosted weights are an owned model", () =>
  expect(ownModel("nutrition_text", () => undefined)).toBeNull());
it("fails closed until a reviewed owned version is in Git", () => {
  expect(() => ownModel("nutrition_text", env)).toThrow("not_configured");
  expect(ownModel("nutrition_text", env, [model])?.id).toBe("meal-v1");
});
it("rejects synthetic, untested, unqualified and unsupported model versions", () => {
  for (const patch of [
    { synthetic: true },
    { runtimeVerified: false },
    { status: "candidate" },
    { weightsSha256: "missing" },
    { cloudflareModel: "arbitrary-paid-model" },
  ])
    expect(() =>
      ownModel("nutrition_text", env, [{ ...model, ...patch }]),
    ).toThrow("not_configured");
});

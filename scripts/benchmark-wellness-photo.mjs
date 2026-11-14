// Operator-only comparison. This module is never imported by the application.
import { readFile, realpath, open } from "node:fs/promises";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { resolve, sep, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { parseArgs } from "node:util";
import { build } from "esbuild";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const hash = (value) => createHash("sha256").update(value).digest("hex");
export const visionModels = Object.freeze({
  current: "@cf/meta/llama-3.2-11b-vision-instruct",
  gemma4: "@cf/google/gemma-4-26b-a4b-it",
});

export function imageType(bytes) {
  if (bytes.length > 5242880) throw Error("invalid_image");
  if (bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) return "image/jpeg";
  if (bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) return "image/png";
  if (bytes.subarray(0, 4).toString() === "RIFF" && bytes.subarray(8, 12).toString() === "WEBP") return "image/webp";
  throw Error("invalid_image");
}

export async function prepareCases(reference, imageRoot, limit) {
  if (!Number.isInteger(limit) || limit < 1 || limit > 10) throw Error("limit_must_be_1_to_10");
  const rows = (await readFile(reference, "utf8")).split(/\r?\n/).filter((line) => line.trim()).map((line) => JSON.parse(line));
  if (!rows.length || new Set(rows.map((r) => r.id)).size !== rows.length) throw Error("unique_reference_ids_required");
  const base = await realpath(imageRoot), cases = [];
  for (const row of rows.slice(0, limit)) {
    if (typeof row.id !== "string" || !row.id || row.task !== "nutrition_photo" || row.synthetic !== false || row.consent_active !== true ||
        row.consent_policy !== "wellness-training-v1" || !row.image || typeof row.image.path !== "string" || !/^[a-f0-9]{64}$/.test(row.image.sha256))
      throw Error("consented_real_photo_required");
    const path = await realpath(resolve(base, row.image.path));
    if (!path.startsWith(base + sep)) throw Error("image_outside_root");
    const bytes = await readFile(path);
    if (hash(bytes) !== row.image.sha256) throw Error("image_hash_mismatch");
    const mime = imageType(bytes), description = row.input?.description ?? "";
    if (typeof description !== "string" || description.length > 2500) throw Error("invalid_description");
    if (description.trim()) throw Error("image_only_description_required");
    // Reference targets/weights never enter prepared inference inputs.
    cases.push({ id: row.id, bytes, mime, description, imageSha256: row.image.sha256 });
  }
  return cases;
}

export function assertFreeExecution(env, accountPlan) {
  if (accountPlan !== "free" || env.CLOUDFLARE_FREE_ONLY !== "true") throw Error("verified_free_account_required");
  if (env.WELLNESS_MODEL_SOURCE === "owned") throw Error("hosted_comparison_only");
  if (!/^[a-f0-9]{32}$/i.test(env.CLOUDFLARE_ACCOUNT_ID ?? "") || !env.CLOUDFLARE_AI_TOKEN) throw Error("credentials_required");
}

export function candidateVisionBody(body, model) {
  if (model === visionModels.current) return body;
  if (model !== visionModels.gemma4) throw Error("unsupported_vision_model");
  const bytes = Buffer.from(body.image, "base64");
  return {
    messages: [{ role: "user", content: [
      { type: "text", text: body.prompt },
      { type: "image_url", image_url: { url: `data:${imageType(bytes)};base64,${body.image}` } },
    ] }],
    temperature: body.temperature,
    max_completion_tokens: body.max_tokens,
    chat_template_kwargs: { enable_thinking: false },
    stream: false, store: false,
  };
}

export async function loadPipeline() {
  const code = await build({
    stdin: { contents: 'export { createProvider, MODELS } from "./supabase/functions/_shared/wellness-provider.ts"; export { observationPrompt, recipeAwareMealPrompt, compactMealSchema, normalizeCompactMeal } from "./supabase/functions/_shared/wellness-food.ts";', resolveDir: root },
    bundle: true, platform: "node", format: "esm", write: false,
  });
  return import(`data:text/javascript;base64,${Buffer.from(code.outputFiles[0].text).toString("base64")}`);
}

export async function inferCase(pipeline, sample, model, env, request = fetch) {
  if (!Object.values(visionModels).includes(model)) throw Error("unsupported_vision_model");
  const account = env.CLOUDFLARE_ACCOUNT_ID;
  const provider = pipeline.createProvider((key) => key === "WELLNESS_AI_ENABLED" ? "true" : env[key], async (url, options) => {
    const baseline = `https://api.cloudflare.com/client/v4/accounts/${account}/ai/run/${visionModels.current}`;
    if (url === baseline) {
      const body = candidateVisionBody(JSON.parse(options.body), model);
      return request(`https://api.cloudflare.com/client/v4/accounts/${account}/ai/run/${model}`, { ...options, body: JSON.stringify(body) });
    }
    return request(url, options);
  });
  const visualObservations = await provider.vision(sample.bytes, pipeline.observationPrompt);
  const raw = await provider.structured(
    pipeline.recipeAwareMealPrompt + "\nSchema: " + JSON.stringify(pipeline.compactMealSchema()),
    { mode: "meal", description: sample.description, visualObservations },
    1800, "nutrition_text", pipeline.compactMealSchema(), true,
  );
  return pipeline.normalizeCompactMeal(raw, true, { visualObservations, description: sample.description });
}

/** @param {object} options @param {Record<string, string | undefined>} env */
export async function runComparison({ reference, imageRoot, output, preset = "current", limit = 5, execute = false, accountPlan }, env = process.env, request = fetch) {
  const model = visionModels[preset];
  if (!model) throw Error("unsupported_vision_model");
  if (execute) assertFreeExecution(env, accountPlan);
  const cases = await prepareCases(reference, imageRoot, limit);
  const pipeline = await loadPipeline();
  const sourceFiles = ["wellness-provider.ts", "wellness-food.ts", "recipe-oil.ts", "wellness-core.ts", "wellness-owned-routing.ts"];
  const sourceHashes = Object.fromEntries(await Promise.all(sourceFiles.map(async (file) => [file, hash(await readFile(resolve(root, "supabase/functions/_shared", file)))])));
  const config = {
    version: 1, scope: "isolated_model_pipeline_without_catalog_or_diary", visionModel: model, normalizer: pipeline.MODELS.mealText,
    visionMaxTokens: 1400, normalizationMaxTokens: 1800, visionTemperature: 0.1, normalizationTemperature: 0.15,
    ...(preset === "gemma4" ? { enableThinking: false } : {}),
    gitRevision: execFileSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim(),
    runnerSha256: hash(await readFile(fileURLToPath(import.meta.url))), sourceHashes,
    promptSha256: hash(pipeline.observationPrompt + pipeline.recipeAwareMealPrompt + JSON.stringify(pipeline.compactMealSchema())),
  };
  const configId = `cf-photo:${hash(JSON.stringify(config))}`;
  const plan = { configId, config, cases: cases.map((c) => ({ id: c.id, imageSha256: c.imageSha256 })), maximumProviderCalls: cases.length * 2 };
  if (!execute) return { dryRun: true, ...plan }; // No credentials or inference needed.
  if (!output) throw Error("output_required");
  // Exclusive creation prevents overwriting predictions or silently resuming a biased run.
  const handle = await open(output, "wx", 0o600);
  let manifest;
  try {
    manifest = await open(output + ".manifest.json", "wx", 0o600);
    await manifest.writeFile(JSON.stringify({ ...plan, accountPlan: "operator_verified_free", startedAt: new Date().toISOString() }, null, 2));
    for (const sample of cases) {
      const started = performance.now();
      let row, stop = false;
      try {
        row = { prediction: await inferCase(pipeline, sample, model, env, request) };
      } catch (e) {
        const error = ["rate_limited", "provider_failed", "invalid_output", "invalid_input"].includes(e?.message) ? e.message : "analysis_failed";
        row = { error }; stop = error === "rate_limited";
      }
      await handle.writeFile(JSON.stringify({ id: sample.id, configId, elapsedMs: Math.round(performance.now() - started), ...row }) + "\n");
      if (stop) throw Error("quota_stopped_partial_run"); // Missing coverage is rejected by photo_benchmark.
    }
  } finally {
    await manifest?.close(); await handle.close();
  }
  return { dryRun: false, configId, cases: cases.length, output };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const { values } = parseArgs({ options: {
      reference: { type: "string" }, "image-root": { type: "string" }, output: { type: "string" }, preset: { type: "string", default: "current" },
      limit: { type: "string", default: "5" }, execute: { type: "boolean", default: false }, "account-plan": { type: "string" },
    } });
    if (!values.reference || !values["image-root"]) throw Error("reference_and_image_root_required");
    console.log(JSON.stringify(await runComparison({ reference: values.reference, imageRoot: values["image-root"], output: values.output,
      preset: values.preset, limit: Number(values.limit), execute: values.execute, accountPlan: values["account-plan"] }), null, 2));
  } catch (e) {
    // Never print provider responses, request bodies, tokens or private inputs.
    const known = /^(verified_free_account_required|hosted_comparison_only|credentials_required|limit_must_be_1_to_10|unique_reference_ids_required|consented_real_photo_required|image_outside_root|image_hash_mismatch|invalid_image|invalid_description|image_only_description_required|unsupported_vision_model|output_required|quota_stopped_partial_run|reference_and_image_root_required)$/;
    console.error(known.test(e?.message) ? e.message : "comparison_failed_check_local_inputs");
    process.exitCode = 1;
  }
}

import { afterEach, expect, it, vi } from "vitest";
import { mkdtemp, writeFile, readFile, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { prepareCases, runComparison, visionModels, candidateVisionBody } from "../../scripts/benchmark-wellness-photo.mjs";

const dirs: string[] = [];
afterEach(async () => { await Promise.all(dirs.splice(0).map((path) => rm(path, { recursive: true, force: true }))); });
const bytes = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const env = { CLOUDFLARE_FREE_ONLY: "true", CLOUDFLARE_ACCOUNT_ID: "a".repeat(32), CLOUDFLARE_AI_TOKEN: "test-only" };
async function fixture() {
  const dir = await mkdtemp(join(tmpdir(), "photo-comparison-")); dirs.push(dir);
  await writeFile(join(dir, "image.png"), bytes);
  const rows = ["one", "two"].map((id) => ({ id, task: "nutrition_photo", synthetic: false, consent_active: true,
    consent_policy: "wellness-training-v1", reviewed: false, input: { description: "" },
    target: { items: [{ name: "SECRET_GROUND_TRUTH", quantity: 123 }] },
    image: { path: "image.png", sha256: createHash("sha256").update(bytes).digest("hex") } }));
  const reference = join(dir, "reference.jsonl"), output = join(dir, "predictions.jsonl");
  await writeFile(reference, rows.map((r) => JSON.stringify(r)).join("\n"));
  return { dir, reference, output, rows };
}

it("prepares a no-network dry run without credentials and never carries ground truth into inference inputs", async () => {
  const f = await fixture(), request = vi.fn();
  const prepared = await prepareCases(f.reference, f.dir, 2);
  expect(JSON.stringify(prepared)).not.toContain("SECRET_GROUND_TRUTH");
  const result = await runComparison({ reference: f.reference, imageRoot: f.dir, output: f.output, execute: false, preset: "gemma4", limit: 2, accountPlan: undefined }, {}, request);
  expect(result.dryRun).toBe(true);
  expect(result).toMatchObject({ maximumProviderCalls: 4, config: { visionModel: visionModels.gemma4 } });
  expect(request).not.toHaveBeenCalled();
  await expect(readFile(f.output)).rejects.toThrow();
  f.rows[0].input.description = "SECRET_GROUND_TRUTH";
  await writeFile(f.reference, f.rows.map((r) => JSON.stringify(r)).join("\n"));
  await expect(prepareCases(f.reference, f.dir, 1)).rejects.toThrow("image_only_description_required");
});

it("blocks inference unless the operator has verified a Free account and supplied the free-only guard", async () => {
  const f = await fixture(), request = vi.fn();
  for (const [settings, accountPlan] of [[env, "paid"], [{ ...env, CLOUDFLARE_FREE_ONLY: "false" }, "free"]] as const) {
    await expect(runComparison({ reference: f.reference, imageRoot: f.dir, output: f.output, execute: true, accountPlan }, settings, request)).rejects.toThrow("verified_free_account_required");
  }
  expect(request).not.toHaveBeenCalled();
});

it("refuses owned-adapter routing in a hosted-model comparison", async () => {
  const f = await fixture(), request = vi.fn();
  await expect(runComparison({ reference: f.reference, imageRoot: f.dir, output: f.output, execute: true, accountPlan: "free" }, { ...env, WELLNESS_MODEL_SOURCE: "owned" }, request)).rejects.toThrow("hosted_comparison_only");
  expect(request).not.toHaveBeenCalled();
});

it("rejects modified images and symlink escapes before any inference", async () => {
  const f = await fixture();
  await writeFile(join(f.dir, "image.png"), Buffer.concat([bytes, Buffer.from([1])]));
  await expect(prepareCases(f.reference, f.dir, 2)).rejects.toThrow("image_hash_mismatch");
  const outside = await mkdtemp(join(tmpdir(), "outside-photo-")); dirs.push(outside);
  await writeFile(join(outside, "other.png"), bytes);
  await symlink(join(outside, "other.png"), join(f.dir, "escape.png"));
  f.rows[0].image.path = "escape.png";
  await writeFile(f.reference, f.rows.map((r) => JSON.stringify(r)).join("\n"));
  await expect(prepareCases(f.reference, f.dir, 1)).rejects.toThrow("image_outside_root");
});

it("uses bounded multimodal Gemma requests with thinking and provider storage disabled", () => {
  const body = candidateVisionBody({ prompt: "Observe this plate", image: bytes.toString("base64"), max_tokens: 1400, temperature: .1 }, visionModels.gemma4);
  expect(body).toMatchObject({ max_completion_tokens: 1400, chat_template_kwargs: { enable_thinking: false }, store: false, stream: false });
  expect(body.messages[0].content[1].image_url.url).toMatch(/^data:image\/png;base64,/);
  expect(() => candidateVisionBody({}, "unapproved")).toThrow("unsupported_vision_model");
});

it("keeps malformed-normalization failures in the prediction file without leaking reference labels", async () => {
  const f = await fixture(), bodies: string[] = [];
  const request = vi.fn<typeof fetch>(async (_url, options) => {
    const body = String(options?.body); bodies.push(body);
    return new Response(JSON.stringify({ success: true, result: { response: bodies.length % 2 ? "One apple." : "not valid JSON" } }));
  });
  await runComparison({ reference: f.reference, imageRoot: f.dir, output: f.output, preset: "current", limit: 2, execute: true, accountPlan: "free" }, env, request);
  const predictions = (await readFile(f.output, "utf8")).trim().split("\n").map((line) => JSON.parse(line));
  expect(predictions.map((p) => p.id)).toEqual(["one", "two"]);
  expect(predictions.every((p) => p.error === "invalid_output" && p.elapsedMs >= 0)).toBe(true);
  expect(bodies.join(" ")).not.toContain("SECRET_GROUND_TRUTH");
  expect(request).toHaveBeenCalledTimes(4);
});

it("stops immediately on quota exhaustion and leaves explicitly partial coverage instead of fabricated samples", async () => {
  const f = await fixture(), request = vi.fn<typeof fetch>(async () => new Response("", { status: 429 }));
  await expect(runComparison({ reference: f.reference, imageRoot: f.dir, output: f.output, execute: true, accountPlan: "free", limit: 2 }, env, request)).rejects.toThrow("quota_stopped_partial_run");
  expect(request).toHaveBeenCalledTimes(1);
  const rows = (await readFile(f.output, "utf8")).trim().split("\n").map((line) => JSON.parse(line));
  expect(rows).toHaveLength(1);
  expect(rows[0].error).toBe("rate_limited");
  await expect(runComparison({ reference: f.reference, imageRoot: f.dir, output: f.output, execute: true, accountPlan: "free", limit: 2 }, env, request)).rejects.toThrow();
  expect(request).toHaveBeenCalledTimes(1); // Existing output is never overwritten.
});

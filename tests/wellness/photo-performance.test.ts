import { expect, it } from "vitest";
import { PhotoPerformance } from "../../supabase/functions/_shared/photo-performance";

it("measures sequential processing stages while preserving their actual return values", async () => {
  let now = 10;
  const timing = new PhotoPerformance(() => now);
  expect(await timing.measure("download", async () => { now += 14.4; return new Uint8Array([1, 2]); })).toEqual(new Uint8Array([1, 2]));
  await timing.measure("vision", async () => { now += 1500; return "observations"; });
  await timing.measure("normalization", async () => { now += 500; return { foods: [] }; });
  const snapshot = timing.snapshot("complete");
  expect(snapshot).toEqual({ version: 1, scope: "server_photo_processing", outcome: "complete", totalMs: 2014, stages: {
    download: { elapsedMs: 14, outcome: "complete" }, vision: { elapsedMs: 1500, outcome: "complete" }, normalization: { elapsedMs: 500, outcome: "complete" },
  } });
  now += 1000;
  expect(timing.snapshot("complete").totalMs).toBe(2014); // excludes later persistence time
  expect(JSON.stringify(snapshot)).not.toContain("observations");
});

it("records a failed stage duration and rethrows the same error without recording private contents", async () => {
  let now = 0;
  const timing = new PhotoPerformance(() => now), error = new Error("private prompt / owner/photo.jpg");
  await expect(timing.measure("vision", async () => { now = 3000; throw error; })).rejects.toBe(error);
  expect(timing.snapshot("failed")).toEqual({ version: 1, scope: "server_photo_processing", outcome: "failed", totalMs: 3000, stages: { vision: { elapsedMs: 3000, outcome: "failed" } } });
  expect(JSON.stringify(timing.snapshot("failed"))).not.toContain("private");
});

it("keeps snapshots and separate request attempts isolated", async () => {
  let now = 0;
  const first = new PhotoPerformance(() => now);
  await first.measure("catalog", async () => { now += 5; });
  const snapshot = first.snapshot("complete");
  snapshot.stages.catalog.elapsedMs = 999;
  expect(first.snapshot("complete").stages.catalog.elapsedMs).toBe(5);
  const retry = new PhotoPerformance(() => now);
  await retry.measure("download", async () => { now += 20; });
  expect(retry.snapshot("failed").totalMs).toBe(20);
  expect(retry.snapshot("failed").stages).not.toHaveProperty("catalog");
});

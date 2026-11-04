import { describe, expect, it } from "vitest";
import samples from "./live-samples.json";
import { parseNutrition, makeProgram, parsePreferences } from "../../supabase/functions/_shared/wellness-core";
import { parseChatAnswer } from "../../supabase/functions/_shared/wellness-chat-core";

describe("captured live provider output (contract regression, not model accuracy)", () => {
  it("accepts measured text/label results and rejects invented image units", () => {
    for (const sample of samples.cases.filter((s) => s.kind === "nutrition")) {
      if (sample.id === "vision-meal-pipeline") {
        expect(() => parseNutrition(sample.output)).toThrow("invalid_output");
      } else {
        expect(() => parseNutrition(sample.output)).not.toThrow();
      }
    }
  });
  it("preserves measured amounts and exact printed label arithmetic", () => {
    for (const id of ["weighed-rice-chicken", "milk-volume", "label-explicit", "vision-label-pipeline"]) {
      const result = parseNutrition(samples.cases.find((s) => s.id === id)!.output);
      for (const item of result.items) {
        expect(item.quantityLow).toBe(item.quantity);
        expect(item.quantityHigh).toBe(item.quantity);
      }
    }
    const item = parseNutrition(samples.cases.find((s) => s.id === "vision-label-pipeline")!.output).items[0];
    expect(item.quantity).toBe(40);
    expect(item.per100.kcal * item.quantity / 100).toBe(100);
    expect(item.per100.sodium! * item.quantity / 100).toBe(160);
    expect(item.per100.fiber).toBeNull();
  });
  it("validates the live program against the real catalog and preference rules", () => {
    const sample = samples.cases.find((s) => s.kind === "program")!;
    const result = makeProgram(sample.output, parsePreferences(sample.preferences), "2026-11-04");
    expect(result.changes).toHaveLength(1);
    expect(result.changes[0].data.exercises.every((e) => e.loadUnknown && e.weight === 0)).toBe(true);
  });
  it("parses live chat output without claiming its language or advice is qualified", () => {
    for (const sample of samples.cases.filter((s) => s.kind === "chat")) {
      expect(() => parseChatAnswer(sample.output)).not.toThrow();
    }
  });
});

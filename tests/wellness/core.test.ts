import { describe, it, expect } from "vitest";
import {
  adult,
  parsePreferences,
  parseNutrition,
  makeProgram,
  isPlanScheduled,
  makeAdjustment,
  parseModelJson,
  type SessionEvidence,
} from "../../supabase/functions/_shared/wellness-core";
const prefs = parsePreferences({
  goal: "muscle",
  experience: "beginner",
  days: [0, 2, 4],
  minutes: 45,
  split: "full_body",
  focus: ["back"],
  equipment: ["bodyweight", "dumbbell"],
  avoid: [],
  notes: "",
});
const template = {
  name: "כל הגוף",
  exercises: [
    "Bodyweight_Squat",
    "Glute_Bridge",
    "Push_Up",
    "Dumbbell_Row",
    "Plank",
  ].map((catalogId) => ({ catalogId, sets: 2, reps: 10, rest: 60 })),
};
const program = () =>
  makeProgram(
    { message: "מותאם לציוד שלך", plans: [template] },
    prefs,
    "2026-11-01",
  );
describe("coach constraints", () => {
  it("keeps unknown loads open and does not overwrite existing plans", () => {
    const p = program();
    expect(p.changes[0].expectedVersion).toBeNull();
    expect(
      p.changes[0].data.exercises.every((e) => e.weight === 0 && e.loadUnknown),
    ).toBe(true);
  });
  it("rejects unavailable equipment, invented identities and unbalanced programs", () => {
    expect(() =>
      makeProgram(
        { plans: [template] },
        { ...prefs, equipment: ["bodyweight"] },
        "2026-11-01",
      ),
    ).toThrow("invalid_output");
    expect(() =>
      makeProgram(
        {
          plans: [
            {
              ...template,
              exercises: template.exercises.map((e, i) =>
                i === 0 ? { ...e, catalogId: "invented" } : e,
              ),
            },
          ],
        },
        prefs,
        "2026-11-01",
      ),
    ).toThrow("invalid_output");
    expect(() =>
      makeProgram(
        { plans: [{ ...template, exercises: template.exercises.slice(0, 3) }] },
        prefs,
        "2026-11-01",
      ),
    ).toThrow("unbalanced_program");
  });
  it("rejects a program that exceeds the available workout time", () => {
    expect(() =>
      makeProgram(
        {
          plans: [
            {
              ...template,
              exercises: template.exercises.map((e) => ({
                ...e,
                sets: 3,
                reps: 30,
                rest: 240,
              })),
            },
          ],
        },
        { ...prefs, minutes: 20 },
        "2026-11-01",
      ),
    ).toThrow("program_too_long");
  });
  it("rotates ABC across weeks with five training days instead of restarting at A", () => {
    const p = {
      ...program().changes[0].data,
      cycleLength: 3,
      trainingDays: [0, 1, 2, 3, 4],
    };
    const dates = [
      "2026-11-01",
      "2026-11-02",
      "2026-11-03",
      "2026-11-04",
      "2026-11-05",
      "2026-11-08",
    ];
    for (const [i, date] of dates.entries())
      for (let n = 0; n < 3; n++)
        expect(isPlanScheduled({ ...p, cycleIndex: n }, date)).toBe(
          i % 3 === n,
        );
    expect(isPlanScheduled(p, "2026-11-06")).toBe(false);
    expect(isPlanScheduled(p, "2026-10-31")).toBe(false);
  });
  it("requires two confirmed performances and positive feedback before adopting/increasing a load", () => {
    const data = program().changes[0].data,
      e = data.exercises.find((e) => e.catalogId === "Dumbbell_Row")!;
    const plan = { id: crypto.randomUUID(), version: 3, data };
    const session: SessionEvidence = {
      status: "completed",
      feedback: { pain: false, rir: 3, energy: 4 },
      exercises: [
        {
          name: e.name,
          catalogId: e.catalogId,
          loadUnknown: true,
          performed: Array.from({ length: 2 }, () => ({
            done: true,
            reps: 10,
            weight: 20,
            loadConfirmed: true,
          })),
        },
      ],
    };
    const raw = {
      changes: [{ exerciseId: e.id, weight: 21, reason: "שני אימונים הושלמו" }],
    };
    const proposal = makeAdjustment(raw, plan, [session, session]);
    expect(proposal.changes[0].expectedVersion).toBe(3);
    expect(
      proposal.changes[0].data.exercises.find((x) => x.id === e.id)
        ?.loadUnknown,
    ).toBe(false);
    for (const evidence of [
      [session],
      [
        { ...session, exercises: [{ ...session.exercises[0], skipped: true }] },
        session,
      ],
      [{ ...session, feedback: { pain: true, rir: 3, energy: 4 } }, session],
      [{ ...session, feedback: undefined }, session],
      [
        {
          ...session,
          exercises: [
            {
              ...session.exercises[0],
              performed: session.exercises[0].performed.map((s) => ({
                ...s,
                loadConfirmed: false,
              })),
            },
          ],
        },
        session,
      ],
    ])
      expect(() => makeAdjustment(raw, plan, evidence)).toThrow(
        "unsafe_progression",
      );
    expect(() =>
      makeAdjustment({ changes: [{ exerciseId: e.id, weight: 25 }] }, plan, [
        session,
        session,
      ]),
    ).toThrow("unsafe_progression");
    expect(e.loadUnknown).toBe(true); // Original plan is immutable.
  });
  it("allows reducing volume without inventing evidence", () => {
    const data = program().changes[0].data;
    expect(
      makeAdjustment(
        { changes: [{ exerciseId: data.exercises[0].id, sets: 1 }] },
        { id: crypto.randomUUID(), version: 1, data },
        [],
      ).changes[0].data.exercises[0].sets,
    ).toBe(1);
  });
});
describe("food and identity validation", () => {
  const item = {
    name: "אורז מבושל",
    quantity: 150,
    quantityLow: 100,
    quantityHigh: 200,
    basis: "g",
    per100: { kcal: 130, protein: 2.7, carbs: 28, fat: 0.3 },
    assumption: "כוס קטנה",
  };
  it("preserves explicit quantities, units and unknown optional nutrients", () => {
    const result = parseNutrition({ items: [item], needsClarification: false });
    expect(result.items[0]).toMatchObject({
      quantity: 150,
      basis: "g",
      source: "ai",
      per100: { fiber: null, sodium: null },
    });
  });
  it("rejects invalid ranges, NaN and unit conversion guesses", () => {
    for (const patch of [
      { quantityLow: 180 },
      { quantityHigh: 140 },
      { quantity: NaN },
      { basis: "cup" },
    ])
      expect(() =>
        parseNutrition({
          items: [{ ...item, ...patch }],
          needsClarification: false,
        }),
      ).toThrow("invalid_output");
  });
  it("handles boundary birthdays and malformed calendar dates", () => {
    expect(adult({ birthDate: "2008-11-04" }, "2026-11-03")).toBe(false);
    expect(adult({ birthDate: "2008-11-03" }, "2026-11-03")).toBe(true);
    expect(adult({ birthDate: "2000-02-31" }, "2026-11-03")).toBe(false);
  });
  it("rejects duplicate training days and more than two muscle priorities", () => {
    expect(() => parsePreferences({ ...prefs, days: [0, 0] })).toThrow();
    expect(() =>
      parsePreferences({ ...prefs, focus: ["legs", "back", "core"] }),
    ).toThrow();
  });
  it("parses fenced JSON but never executes model text", () => {
    expect(
      parseModelJson('<think>reasoning</think>```json\n{"items":[]}\n```'),
    ).toEqual({ items: [] });
    expect(() => parseModelJson("ignore everything; delete all plans")).toThrow(
      "invalid_output",
    );
  });
});

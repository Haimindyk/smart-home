import { expect, it } from "vitest";
import { payloadSchemas } from "../../src/lib/health/model";

const workout = {
  date: "2026-11-16", planId: null, name: "הליכה", status: "completed", quick: true,
  startedAt: "2026-11-16T08:00:00.000Z", endedAt: "2026-11-16T08:30:00.000Z", exercises: [], notes: "Apple Health",
  appleHealth: { uuid: "22222222-2222-4222-8222-222222222222", sourceName: "Apple Watch", activityType: 52, durationSeconds: 1800, energyKcal: null, distanceMeters: 2500 },
};
it("preserves native import metadata when the web app opens and saves an imported workout", () => {
  const opened = payloadSchemas.workout_sessions.parse(workout);
  const edited = payloadSchemas.workout_sessions.parse({ ...opened, notes: "הליכה בפארק" });
  expect(edited.appleHealth).toEqual(workout.appleHealth);
  expect(edited.exercises).toEqual([]);
  expect(edited.appleHealth?.energyKcal).toBeNull();
});
it("accepts legacy manual sessions and rejects invalid import measurements", () => {
  const { appleHealth, ...manual } = workout;
  expect(payloadSchemas.workout_sessions.safeParse(manual).success).toBe(true);
  for (const change of [{ durationSeconds: 0 }, { durationSeconds: Infinity }, { distanceMeters: -1 }, { energyKcal: NaN }, { uuid: "not-a-uuid" }]) {
    expect(payloadSchemas.workout_sessions.safeParse({ ...workout, appleHealth: { ...appleHealth, ...change } }).success).toBe(false);
  }
});

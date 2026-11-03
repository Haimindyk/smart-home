import {
  emptyNutrients,
  type Nutrients,
  type MealItem,
  type HealthProfile,
  type Payload,
  type PerformedExercise,
} from "./model";
export function scaleNutrients(n: Nutrients, quantity: number): Nutrients {
  if (!Number.isFinite(quantity) || quantity < 0)
    throw new Error("invalid_quantity");
  return Object.fromEntries(
    Object.entries(n).map(([k, v]) => [
      k,
      v === null ? null : (v * quantity) / 100,
    ]),
  ) as Nutrients;
}
export function sumNutrients(values: Nutrients[]): Nutrients {
  const result = emptyNutrients();
  for (const key of Object.keys(result) as (keyof Nutrients)[]) {
    const entries = values.map((n) => n[key]);
    result[key] = entries.some((v) => v === null)
      ? (null as never)
      : entries.reduce<number>((s, n) => s + (n ?? 0), 0);
  }
  return result;
}
export const mealNutrients = (items: MealItem[]) =>
  sumNutrients(items.map((i) => scaleNutrients(i.food.per100, i.quantity)));
/** Calendar age: birthdays advance in the user's date, without timezone offsets. */
export function ageOnDate(birthDate: string, date: string): number {
  const valid = (v: string) => /^\d{4}-\d{2}-\d{2}$/.test(v) && !Number.isNaN(Date.parse(v)) && new Date(v).toISOString().slice(0,10) === v;
  if (!valid(birthDate) || !valid(date) || birthDate > date) throw new Error("invalid_birth_date");
  const age = Number(date.slice(0,4)) - Number(birthDate.slice(0,4)) - (date.slice(5) < birthDate.slice(5) ? 1 : 0);
  if(age > 120) throw new Error("invalid_birth_date");
  return age;
}
export function calculateGoal(
  p: HealthProfile,
  date: string,
): Payload<"nutrition_goals"> {
  const age = p.birthDate ? ageOnDate(p.birthDate, date) : p.age;
  if (!age || age < 18 || !p.weight || !p.height || !p.physiology)
    throw new Error("adult_profile_required");
  const bmr =
    10 * p.weight +
    6.25 * p.height -
    5 * age +
    (p.physiology === "male" ? 5 : -161);
  const activity = {
    sedentary: 1.2,
    light: 1.375,
    moderate: 1.55,
    high: 1.725,
  }[p.activity];
  const multiplier = { lose: 0.9, maintain: 1, gain: 1.05 }[p.objective];
  const kcal = Math.round(Math.max(bmr, bmr * activity * multiplier));
  const protein = Math.round(p.weight * 1.6),
    fat = Math.round((kcal * 0.25) / 9);
  return {
    date,
    kcal,
    protein,
    fat,
    carbs: Math.max(0, Math.round((kcal - protein * 4 - fat * 9) / 4)),
    method: "calculated",
  };
}
export function goalForDate(goals: Payload<"nutrition_goals">[], date: string) {
  return (
    goals
      .filter((g) => g.date <= date)
      .sort((a, b) => b.date.localeCompare(a.date))[0] ?? null
  );
}
export function localDate(timezone: string, now = new Date()) {
  const parts = new Intl.DateTimeFormat("en", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(now);
  const get = (type: string) => parts.find((p) => p.type === type)?.value;
  return `${get("year")}-${get("month")}-${get("day")}`;
}
export function workoutVolume(exercises: PerformedExercise[]) {
  return exercises
    .filter((e) => e.kind === "strength" && !e.skipped && !e.holdSeconds)
    .reduce(
      (total, e) =>
        total +
        e.performed
          .filter((s) => s.done)
          .reduce((sum, s) => sum + s.reps * s.weight, 0),
      0,
    );
}
export function dateRange(end: string, days: number) {
  return Array.from({ length: days }, (_, i) => {
    const d = new Date(`${end}T12:00:00Z`);
    d.setUTCDate(d.getUTCDate() - days + i + 1);
    return d.toISOString().slice(0, 10);
  });
}
export function csvEscape(value: unknown) {
  return `"${String(value ?? "")
    .replace(/^[=+@\-\t\r]/, "'$&")
    .replaceAll('"', '""')}"`;
}

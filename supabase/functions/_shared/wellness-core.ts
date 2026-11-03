import { wellnessExercises } from "./exercise-catalog.ts";
export type Split = "auto" | "full_body" | "ab" | "abc" | "custom";
export type TrainingPreferences = {
  goal: "strength" | "muscle" | "fitness";
  experience: "beginner" | "intermediate" | "advanced";
  days: number[];
  minutes: number;
  split: Split;
  focus: string[];
  equipment: string[];
  avoid: string[];
  notes: string;
};
export type PlanExercise = {
  id: string;
  catalogId?: string;
  demoId?: string;
  name: string;
  muscle: string;
  equipment: string;
  kind: "strength" | "cardio";
  sets: number;
  reps: number;
  repMax?: number;
  weight: number;
  loadUnknown: boolean;
  rest: number;
  duration: number;
  distance: number;
  notes: string;
  holdSeconds?: number;
};
export type PlanData = {
  name: string;
  exercises: PlanExercise[];
  days: number[];
  archived: boolean;
  notes: string;
  programId?: string;
  split?: string;
  cycleIndex?: number;
  cycleLength?: number;
  startDate?: string;
  trainingDays?: number[];
};
export type PlanChange = {
  id: string;
  expectedVersion: number | null;
  data: PlanData;
};
export type CoachProposal = {
  message: string;
  changes: PlanChange[];
  reasons: string[];
  kind: "program" | "adjustment" | "restore";
};
export type NutritionItem = {
  name: string;
  quantity: number;
  quantityLow: number;
  quantityHigh: number;
  basis: "g" | "ml";
  per100: {
    kcal: number;
    protein: number;
    carbs: number;
    fat: number;
    fiber: number | null;
    sugar: number | null;
    saturatedFat: number | null;
    sodium: number | null;
  };
  source: "ai" | "usda" | "manual" | "recipe" | "openfoodfacts" | "label";
  sourceId?: string;
  assumption: string;
};
export type NutritionEstimate = {
  items: NutritionItem[];
  needsClarification: boolean;
  question: string;
};
export function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new Error("invalid_output");
  return value as Record<string, unknown>;
}
export function number(value: unknown, low: number, high: number) {
  if (
    typeof value !== "number" ||
    !Number.isFinite(value) ||
    value < low ||
    value > high
  )
    throw new Error("invalid_output");
  return value;
}
export function text(value: unknown, max = 1000) {
  if (typeof value !== "string" || value.length > max)
    throw new Error("invalid_output");
  return value.trim();
}
export function parsePreferences(value: unknown): TrainingPreferences {
  const p = record(value);
  const choices = (v: unknown, allowed: string[]) => {
    if (typeof v !== "string" || !allowed.includes(v))
      throw new Error("invalid_input");
    return v;
  };
  const list = (v: unknown, allowed: string[], limit: number) => {
    if (
      !Array.isArray(v) ||
      v.length > limit ||
      v.some((x) => typeof x !== "string" || !allowed.includes(x)) ||
      new Set(v).size !== v.length
    )
      throw new Error("invalid_input");
    return v as string[];
  };
  if (
    !Array.isArray(p.days) ||
    p.days.some((d) => !Number.isInteger(d) || d < 0 || d > 6)
  )
    throw new Error("invalid_input");
  const days = list(
    p.days.map(String),
    ["0", "1", "2", "3", "4", "5", "6"],
    6,
  ).map(Number);
  if (!days.length) throw new Error("invalid_input");
  return {
    goal: choices(p.goal, [
      "strength",
      "muscle",
      "fitness",
    ]) as TrainingPreferences["goal"],
    experience: choices(p.experience, [
      "beginner",
      "intermediate",
      "advanced",
    ]) as TrainingPreferences["experience"],
    days: days.sort(),
    minutes: number(p.minutes, 20, 120),
    split: choices(p.split, [
      "auto",
      "full_body",
      "ab",
      "abc",
      "custom",
    ]) as Split,
    focus: list(
      p.focus,
      [
        "legs",
        "hamstrings",
        "glutes",
        "chest",
        "back",
        "shoulders",
        "biceps",
        "triceps",
        "calves",
        "core",
      ],
      2,
    ),
    equipment: list(
      p.equipment,
      ["bodyweight", "dumbbell", "barbell", "machine", "cable", "pullup"],
      6,
    ),
    avoid: list(
      p.avoid,
      wellnessExercises.map((e) => e.id),
      35,
    ),
    notes: text(p.notes, 1000),
  };
}
export function effectiveSplit(p: TrainingPreferences): Exclude<Split, "auto"> {
  return p.split === "auto"
    ? p.days.length <= 3
      ? "full_body"
      : p.days.length === 4
        ? "ab"
        : "abc"
    : p.split;
}
export function parseNutrition(raw: unknown): NutritionEstimate {
  const obj = record(raw);
  if (
    !Array.isArray(obj.items) ||
    obj.items.length > 30 ||
    typeof obj.needsClarification !== "boolean"
  )
    throw new Error("invalid_output");
  const items = obj.items.map((raw) => {
    const i = record(raw),
      n = record(i.per100);
    const quantity = number(i.quantity, 0.1, 10000);
    const quantityLow = number(i.quantityLow ?? quantity, 0.1, 10000),
      quantityHigh = number(i.quantityHigh ?? quantity, 0.1, 10000);
    if (
      quantityLow > quantity ||
      quantityHigh < quantity ||
      !["g", "ml"].includes(String(i.basis))
    )
      throw new Error("invalid_output");
    const optional = (key: string, max: number) =>
      n[key] == null ? null : number(n[key], 0, max);
    const name = text(i.name, 200);
    if (!name) throw new Error("invalid_output");
    return {
      name,
      quantity,
      quantityLow,
      quantityHigh,
      basis: i.basis as "g" | "ml",
      assumption: text(i.assumption ?? ""),
      source: "ai" as const,
      per100: {
        kcal: number(n.kcal, 0, 10000),
        protein: number(n.protein, 0, 1000),
        carbs: number(n.carbs, 0, 1000),
        fat: number(n.fat, 0, 1000),
        fiber: optional("fiber", 1000),
        sugar: optional("sugar", 1000),
        saturatedFat: optional("saturatedFat", 1000),
        sodium: optional("sodium", 100000),
      },
    };
  });
  return {
    items,
    needsClarification: obj.needsClarification,
    question: text(obj.question ?? ""),
  };
}
export function makeProgram(
  raw: unknown,
  p: TrainingPreferences,
  startDate: string,
): CoachProposal {
  const r = record(raw),
    split = effectiveSplit(p),
    expected =
      split === "full_body"
        ? 1
        : split === "ab"
          ? 2
          : split === "abc"
            ? 3
            : p.days.length;
  if (!Array.isArray(r.plans) || r.plans.length !== expected)
    throw new Error("invalid_output");
  const programId = crypto.randomUUID();
  const changes = r.plans.map((raw, index) => {
    const plan = record(raw);
    if (
      !Array.isArray(plan.exercises) ||
      plan.exercises.length < 3 ||
      plan.exercises.length > 10
    )
      throw new Error("invalid_output");
    const ids = new Set<string>();
    const exercises = plan.exercises.map((raw) => {
      const e = record(raw),
        c = wellnessExercises.find((c) => c.id === e.catalogId);
      if (
        !c ||
        ids.has(c.id) ||
        p.avoid.includes(c.id) ||
        !p.equipment.includes(c.equipment)
      )
        throw new Error("invalid_output");
      ids.add(c.id);
      const sets = number(e.sets, 1, p.experience === "beginner" ? 3 : 5),
        reps = number(e.reps, 3, 30),
        rest = number(e.rest, 30, 240);
      if (
        !Number.isInteger(sets) ||
        !Number.isInteger(reps) ||
        !Number.isInteger(rest)
      )
        throw new Error("invalid_output");
      return {
        id: crypto.randomUUID(),
        catalogId: c.id,
        demoId: c.demoId,
        name: c.he,
        muscle: c.muscle,
        equipment: c.equipment,
        kind: "strength" as const,
        sets,
        reps,
        weight: 0,
        loadUnknown: true,
        rest,
        duration: 0,
        distance: 0,
        notes: "",
        ...(c.id === "Plank" ? { holdSeconds: 30, reps: 1 } : {}),
      };
    });
    const estimatedSeconds =
      300 +
      exercises.reduce(
        (sum, e) =>
          sum +
          e.sets * (e.holdSeconds ?? e.reps * 3) +
          Math.max(0, e.sets - 1) * e.rest +
          45,
        0,
      );
    if (estimatedSeconds > p.minutes * 60) throw new Error("program_too_long");
    return {
      id: crypto.randomUUID(),
      expectedVersion: null,
      data: {
        name: text(plan.name, 150) || `${split.toUpperCase()} ${index + 1}`,
        exercises,
        days: p.days,
        archived: false,
        notes: text(plan.notes ?? "", 2000),
        programId,
        split,
        cycleIndex: index,
        cycleLength: expected,
        startDate,
        trainingDays: p.days,
      },
    };
  });
  const all = changes.flatMap((c) => c.data.exercises),
    patterns = new Set<string>(
      all.map(
        (e) => wellnessExercises.find((c) => c.id === e.catalogId)!.pattern,
      ),
    );
  if (!["push", "pull", "squat", "hinge", "core"].every((k) => patterns.has(k)))
    throw new Error("unbalanced_program");
  if (p.focus.some((m) => !all.some((e) => e.muscle === m)))
    throw new Error("unbalanced_program");
  return {
    kind: "program",
    message: text(r.message ?? "", 2000),
    reasons: [],
    changes,
  };
}
export function isPlanScheduled(
  plan: Pick<
    Partial<PlanData>,
    | "programId"
    | "startDate"
    | "trainingDays"
    | "cycleIndex"
    | "cycleLength"
    | "days"
  >,
  date: string,
): boolean {
  const day = new Date(`${date}T12:00:00Z`).getUTCDay();
  if (
    !plan.programId ||
    !plan.startDate ||
    !plan.trainingDays ||
    plan.cycleIndex == null ||
    !plan.cycleLength
  )
    return !!plan.days?.includes(day);
  const start = Date.parse(`${plan.startDate}T12:00:00Z`),
    end = Date.parse(`${date}T12:00:00Z`);
  if (
    !Number.isFinite(start) ||
    end < start ||
    !plan.trainingDays.includes(day)
  )
    return false;
  const elapsed = Math.floor((end - start) / 86400000);
  let count = Math.floor(elapsed / 7) * plan.trainingDays.length;
  for (let n = 0; n <= elapsed % 7; n++)
    if (plan.trainingDays.includes(new Date(start + n * 86400000).getUTCDay()))
      count++;
  return (count - 1) % plan.cycleLength === plan.cycleIndex;
}
export function adult(profile: Record<string, unknown>, today: string) {
  if (
    typeof profile.birthDate === "string" &&
    /^\d{4}-\d{2}-\d{2}$/.test(profile.birthDate)
  ) {
    const birth = new Date(profile.birthDate);
    if (
      Number.isNaN(birth.getTime()) ||
      birth.toISOString().slice(0, 10) !== profile.birthDate
    )
      return false;
    const age =
      Number(today.slice(0, 4)) -
      Number(profile.birthDate.slice(0, 4)) -
      (today.slice(5) < profile.birthDate.slice(5) ? 1 : 0);
    return age >= 18 && age <= 120;
  }
  return (
    typeof profile.age === "number" && profile.age >= 18 && profile.age <= 120
  );
}
export function parseModelJson(output: string): unknown {
  const clean = output
    .replace(/<think>[\s\S]*?<\/think>/g, "")
    .trim()
    .replace(/^```(?:json)?\s*/, "")
    .replace(/\s*```$/, "");
  try {
    return JSON.parse(clean);
  } catch {
    throw new Error("invalid_output");
  }
}

export type SessionEvidence = {
  status: string;
  feedback?: { pain: boolean; rir: number | null; energy: number };
  exercises: {
    name: string;
    catalogId?: string;
    loadUnknown?: boolean;
    skipped?: boolean;
    performed: {
      done: boolean;
      reps: number;
      weight: number;
      loadConfirmed?: boolean;
    }[];
  }[];
};
export function makeAdjustment(
  raw: unknown,
  plan: { id: string; version: number; data: PlanData },
  sessions: SessionEvidence[],
  preferences?: TrainingPreferences,
): CoachProposal {
  const r = record(raw);
  if (
    !Array.isArray(r.changes) ||
    r.changes.length > plan.data.exercises.length
  )
    throw new Error("invalid_output");
  const ids = new Set<string>(),
    reasons: string[] = [];
  const exercises = plan.data.exercises.map((e) => ({ ...e }));
  for (const value of r.changes) {
    const c = record(value),
      e = exercises.find((e) => e.id === c.exerciseId);
    if (!e || ids.has(e.id)) throw new Error("invalid_output");
    ids.add(e.id);
    const sets = number(c.sets ?? e.sets, 1, 5),
      reps = number(c.reps ?? e.reps, 1, 30),
      weight = number(c.weight ?? e.weight, 0, 1000),
      rest = number(c.rest ?? e.rest, 30, 240);
    if (
      !Number.isInteger(sets) ||
      !Number.isInteger(reps) ||
      !Number.isInteger(rest)
    )
      throw new Error("invalid_output");
    const evidence = sessions
      .filter(
        (s) =>
          s.status === "completed" &&
          s.exercises.some((x) =>
            e.catalogId ? x.catalogId === e.catalogId : x.name === e.name,
          ),
      )
      .slice(0, 2);
    const matching = (s: SessionEvidence) =>
      s.exercises.find(
        (x) =>
          !x.skipped &&
          (e.catalogId ? x.catalogId === e.catalogId : x.name === e.name),
      );
    // Unknown starting loads can only become known from explicitly confirmed sets.
    const confirmed = evidence.flatMap(
      (s) =>
        matching(s)
          ?.performed.filter(
            (set) =>
              set.done &&
              (!matching(s)?.loadUnknown || set.loadConfirmed === true),
          )
          .map((set) => set.weight) ?? [],
    );
    const baseline = e.loadUnknown
      ? confirmed.length
        ? Math.min(...confirmed)
        : null
      : e.weight;
    const eligible =
      baseline !== null &&
      evidence.length === 2 &&
      evidence.every(
        (s) =>
          s.feedback &&
          !s.feedback.pain &&
          s.feedback.energy >= 3 &&
          s.feedback.rir != null &&
          s.feedback.rir >= 2 &&
          (matching(s)?.performed.filter(
            (set) =>
              set.done &&
              (!matching(s)?.loadUnknown || set.loadConfirmed === true) &&
              set.reps >= (e.repMax ?? e.reps) &&
              set.weight >= baseline,
          ).length ?? 0) >= e.sets,
      );
    const increase =
      sets > e.sets || reps > e.reps || weight > (baseline ?? e.weight);
    const adoptsLoad = e.loadUnknown && weight > 0;
    if (
      (increase || adoptsLoad) &&
      (!eligible ||
        sessions
          .filter((s) => s.status === "completed")
          .slice(0, 2)
          .some((s) => s.feedback?.pain) ||
        sets > e.sets + 1 ||
        reps > e.reps + 2 ||
        weight > (baseline ?? 0) * 1.05 + 0.001)
    )
      throw new Error("unsafe_progression");
    if (adoptsLoad) e.loadUnknown = false;
    if (c.catalogId && c.catalogId !== e.catalogId) {
      const replacement = wellnessExercises.find((x) => x.id === c.catalogId);
      if (
        !replacement ||
        !preferences ||
        !preferences.equipment.includes(replacement.equipment) ||
        preferences.avoid.includes(replacement.id)
      )
        throw new Error("invalid_output");
      if (weight !== 0) throw new Error("unsafe_progression");
      Object.assign(e, {
        catalogId: replacement.id,
        demoId: replacement.demoId,
        name: replacement.he,
        muscle: replacement.muscle,
        equipment: replacement.equipment,
        loadUnknown: true,
      });
    }
    Object.assign(e, { sets, reps, weight, rest });
    reasons.push(text(c.reason ?? "", 1000));
  }
  return {
    kind: "adjustment",
    message: text(r.message ?? "", 2000),
    reasons,
    changes: r.changes.length
      ? [
          {
            id: plan.id,
            expectedVersion: plan.version,
            data: { ...plan.data, exercises },
          },
        ]
      : [],
  };
}

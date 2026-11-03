import { wellnessExercises } from "../../../supabase/functions/_shared/exercise-catalog";
export const exerciseCatalog = [
  ...wellnessExercises.map((e) => ({
    ...e,
    catalogId: e.id,
    kind: "strength" as const,
  })),
  ...[
    { id: "Walking", he: "הליכה", en: "Walking", equipment: "none" },
    { id: "Running", he: "ריצה", en: "Running", equipment: "none" },
    { id: "Cycling", he: "רכיבה", en: "Cycling", equipment: "bike" },
  ].map((e) => ({
    ...e,
    catalogId: undefined,
    demoId: undefined,
    muscle: "cardio",
    kind: "cardio" as const,
  })),
];

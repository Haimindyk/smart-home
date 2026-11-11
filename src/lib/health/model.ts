import { z } from "zod";
import { parsePreferences, type TrainingPreferences } from "../../../supabase/functions/_shared/wellness-core";

export const nutrientsSchema = z.object({
  kcal: z.number().finite().min(0).max(10000),
  protein: z.number().finite().min(0).max(1000),
  carbs: z.number().finite().min(0).max(1000),
  fat: z.number().finite().min(0).max(1000),
  fiber: z.number().finite().min(0).nullable().default(null),
  sugar: z.number().finite().min(0).nullable().default(null),
  saturatedFat: z.number().finite().min(0).nullable().default(null),
  sodium: z.number().finite().min(0).nullable().default(null),
});
export type Nutrients = z.infer<typeof nutrientsSchema>;
export const unitWeightSchema = z.object({
  low: z.number().finite().positive().max(10000),
  high: z.number().finite().positive().max(10000),
}).refine((v) => v.low <= v.high, "invalid_weight_range");
export const foodSchema = z.object({
  id: z.string(),
  name: z.string().trim().min(1).max(200),
  nameEn: z.string().max(200).optional(),
  barcode: z
    .string()
    .regex(/^\d{8,14}$/)
    .optional(),
  per100: nutrientsSchema,
  basis: z.enum(["g", "ml"]).default("g"),
  servingSize: z.number().positive().optional(),
  // A user-confirmed weight for ONE unit of this specific product, never a
  // category-wide photo heuristic. Ranges remain ranges, not measured facts.
  unitWeight: unitWeightSchema.optional(),
  source: z.enum(["usda", "openfoodfacts", "label", "manual", "ai", "recipe"]),
  sourceId: z.string().optional(),
});
export type Food = z.infer<typeof foodSchema>;
export const mealItemSchema = z.object({
  id: z.string().uuid(),
  food: foodSchema,
  quantity: z.number().finite().positive().max(10000),
  assumption: z.string().max(1000).optional(),
  quantityRange: z.object({low:z.number().positive(),high:z.number().positive()}).optional(),
});
export type MealItem = z.infer<typeof mealItemSchema>;
export const exerciseSchema = z.object({
  id: z.string().uuid(),
  name: z.string().trim().min(1).max(150),
  catalogId: z.string().regex(/^[A-Za-z0-9_-]+$/).max(100).optional(),
  alternativeDemoId: z.string().regex(/^[A-Za-z0-9_-]+$/).max(100).optional(),
  demoId: z.string().regex(/^[A-Za-z0-9_-]+$/).max(100).optional(),
  repMax: z.number().int().min(1).max(500).optional(),
  weightMax: z.number().min(0).max(1000).optional(),
  loadUnknown: z.boolean().optional(),
  holdSeconds: z.number().min(1).max(3600).optional(),
  holdSecondsMax: z.number().min(1).max(3600).optional(),
  muscle: z.string().max(80).default(""),
  equipment: z.string().max(80).default(""),
  kind: z.enum(["strength", "cardio"]).default("strength"),
  sets: z.number().int().min(1).max(30).default(3),
  reps: z.number().int().min(1).max(500).default(10),
  weight: z.number().min(0).max(1000).default(0),
  rest: z.number().int().min(0).max(1800).default(90),
  duration: z.number().min(0).max(1440).default(0),
  distance: z.number().min(0).max(1000).default(0),
  notes: z.string().max(2000).default(""),
});
export type Exercise = z.infer<typeof exerciseSchema>;
export const setSchema = z.object({
  loadConfirmed: z.boolean().optional(),
  seconds: z.number().min(0).max(3600).optional(),
  id: z.string().uuid(),
  reps: z.number().int().min(0).max(500),
  weight: z.number().min(0).max(1000),
  done: z.boolean(),
  duration: z.number().min(0).max(1440).default(0),
  distance: z.number().min(0).max(1000).default(0),
});
export const performedSchema = exerciseSchema.extend({
  performed: z.array(setSchema).max(50),
  skipped: z.boolean().default(false),
});
export type PerformedExercise = z.infer<typeof performedSchema>;
const dateSchema = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/)
  .refine(
    (v) =>
      !Number.isNaN(Date.parse(v)) &&
      new Date(v).toISOString().slice(0, 10) === v,
  );
export const profileSchema = z.object({
  nutritionEnabled: z.boolean().default(false),
  workoutsEnabled: z.boolean().default(false),
  timezone: z
    .string()
    .refine((v) => {
      try {
        new Intl.DateTimeFormat("en", { timeZone: v });
        return true;
      } catch {
        return false;
      }
    })
    .default("Asia/Jerusalem"),
  birthDate: dateSchema.nullable().default(null),
  // Read old profiles without inventing a date of birth.
  age: z.number().int().min(1).max(120).nullable().default(null),
  height: z.number().min(80).max(250).nullable().default(null),
  weight: z.number().min(20).max(400).nullable().default(null),
  physiology: z.enum(["male", "female"]).nullable().default(null),
  activity: z.enum(["sedentary", "light", "moderate", "high"]).default("light"),
  objective: z.enum(["lose", "maintain", "gain"]).default("maintain"),
  waterTarget: z.number().int().min(250).max(10000).default(2000),
  aiConsent: z.boolean().default(false),
  aiProviderConsent: z.boolean().default(false),
  trainingPreferences: z.custom<TrainingPreferences>((value)=>{try{parsePreferences(value);return true;}catch{return false;}}).optional(),
});
export type HealthProfile = z.infer<typeof profileSchema>;
export const payloadSchemas = {
  health_profiles: profileSchema,
  nutrition_goals: z.object({
    date: dateSchema,
    kcal: z.number().min(500).max(10000),
    protein: z.number().min(0).max(500),
    carbs: z.number().min(0).max(1500),
    fat: z.number().min(0).max(500),
    method: z.enum(["manual", "calculated"]),
  }),
  personal_foods: foodSchema,
  recipes: z.object({
    name: z.string().trim().min(1).max(200),
    servings: z.number().positive().max(1000),
    items: z.array(mealItemSchema).min(1).max(100),
  }),
  meals: z.object({
    date: dateSchema,
    kind: z.enum(["breakfast", "lunch", "dinner", "snack"]),
    name: z.string().max(200).default(""),
    items: z.array(mealItemSchema).min(1).max(100),
    imagePath: z.string().max(500).nullable().default(null),
    aiEstimate: z.object({ analysisId:z.string().uuid(), lastCorrectionId:z.string().uuid().optional() }).optional(),
  }),
  water_logs: z.object({
    date: dateSchema,
    amount: z.number().int().positive().max(5000),
  }),
  weight_logs: z.object({
    date: dateSchema,
    weight: z.number().min(20).max(400),
  }),
  workout_plans: z.object({
    programId:z.string().uuid().optional(),
    split:z.string().max(20).optional(),
    cycleIndex:z.number().int().min(0).max(5).optional(),
    cycleLength:z.number().int().min(1).max(6).optional(),
    startDate:dateSchema.optional(),
    trainingDays:z.array(z.number().int().min(0).max(6)).max(6).optional(),
    notes: z.string().max(8000).optional(),
    durationWeeks: z.number().int().min(1).max(104).optional(),
    name: z.string().trim().min(1).max(150),
    exercises: z.array(exerciseSchema).min(1).max(100),
    days: z.array(z.number().int().min(0).max(6)).max(7),
    archived: z.boolean().default(false),
  }),
  workout_sessions: z.object({
    feedback:z.object({energy:z.number().int().min(1).max(5),rir:z.number().int().min(0).max(5).nullable(),pain:z.boolean()}).optional(),
    programNotes: z.string().max(8000).optional(),
    date: dateSchema,
    planId: z.string().uuid().nullable(),
    name: z.string().min(1).max(150),
    status: z.enum(["active", "partial", "completed", "cancelled"]),
    quick: z.boolean().default(false),
    startedAt: z.string().datetime(),
    endedAt: z.string().datetime().nullable().default(null),
    exercises: z.array(performedSchema).max(100),
    notes: z.string().max(4000).default(""),
  }),
} as const;
export type HealthTable = keyof typeof payloadSchemas;
export const healthTables = Object.keys(payloadSchemas) as HealthTable[];
export type Payload<T extends HealthTable> = z.infer<
  (typeof payloadSchemas)[T]
>;
export type HealthRow<T extends HealthTable = HealthTable> = {
  id: string;
  owner_user_id: string;
  data: Payload<T>;
  version: number;
  last_mutation_id?: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
};
export type HealthData = { [T in HealthTable]: HealthRow<T>[] };
export const emptyHealthData = (): HealthData => ({
  health_profiles: [],
  nutrition_goals: [],
  personal_foods: [],
  recipes: [],
  meals: [],
  water_logs: [],
  weight_logs: [],
  workout_plans: [],
  workout_sessions: [],
});
export const emptyNutrients = (): Nutrients => ({
  kcal: 0,
  protein: 0,
  carbs: 0,
  fat: 0,
  fiber: null,
  sugar: null,
  saturatedFat: null,
  sodium: null,
});

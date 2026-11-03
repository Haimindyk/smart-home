import { create } from "zustand";
import { profileSchema } from "../../../src/lib/health/model";
import {
  makeProgram,
  parsePreferences,
} from "../../../supabase/functions/_shared/wellness-core";
const calls: { action: string; table?: string }[] = [];
const profile = {
  id: crypto.randomUUID(),
  version: 1,
  data: profileSchema.parse({
    birthDate: new URLSearchParams(location.search).has("minor")
      ? "2015-01-01"
      : "1990-01-01",
    aiProviderConsent: true,
    nutritionEnabled: true,
    workoutsEnabled: true,
  }),
};
const data: Record<string, unknown[]> = {
  health_profiles: [profile],
  workout_plans: [],
  workout_sessions: [],
  meals: [
    {
      id: "00000000-0000-4000-8000-000000000001",
      version: 1,
      data: {
        date: "2026-11-03",
        name: "Training fixture meal",
        kind: "lunch",
        items: [
          {
            id: crypto.randomUUID(),
            quantity: 100,
            food: {
              id: "apple",
              name: "Synthetic apple",
              source: "manual",
              basis: "g",
              per100: { kcal: 50, protein: 0, carbs: 12, fat: 0 },
            },
          },
        ],
        imagePath: null,
      },
    },
  ],
  water_logs: [],
  weight_logs: [],
  nutrition_goals: [],
  personal_foods: [],
  recipes: [],
};
export const useHealthStore = create(() => ({
  owner: "11111111-1111-4111-8111-111111111111",
  pending: 0,
  data,
  save: async (table: string, value: unknown) => {
    calls.push({ action: "save", table });
    return value;
  },
  remove: async () => {},
  refresh: async () => {},
}));
export const useHealthText = () => (he: string, en: string) =>
  document.documentElement.lang === "he" ? he : en;
export const lookupFood = async () => ({ foods: [] });
export const uploadMealImage = async () =>
  `${useHealthStore.getState().owner}/test.jpg`;
export const createClient = () => ({
  storage: {
    from: () => ({
      createSignedUrl: async () => ({ data: { signedUrl: "" } }),
    }),
  },
});
let consent = false,
  contributions = 0;
export async function healthFunction(
  name: string,
  input: Record<string, unknown>,
) {
  calls.push({ action: String(input.action) });
  if (name === "wellness-training") {
    if (input.action === "status")
      return { enabled: consent, count: contributions };
    if (input.action === "consent") {
      consent = Boolean(input.enabled);
      if (!consent) contributions = 0;
      return { ok: true };
    }
    if (input.action === "submit") {
      if (!consent || input.confirmShare !== true)
        throw new Error("training_consent_required");
      contributions++;
      return { id: "fixture", reviewed: false };
    }
    return { examples: [] };
  }
  if (input.action === "capabilities")
    return { available: true, serviceReady: true };
  if (input.action === "program")
    return {
      ...makeProgram(
        {
          message: "תוכנית אישית לבדיקה",
          plans: [
            {
              name: "Full Body",
              exercises: [
                "Bodyweight_Squat",
                "Glute_Bridge",
                "Push_Up",
                "Dumbbell_Row",
                "Plank",
              ].map((catalogId) => ({
                catalogId,
                sets: 2,
                reps: 10,
                rest: 60,
              })),
            },
          ],
        },
        parsePreferences(input.preferences),
        String(input.date),
      ),
      requestId: input.requestId,
    };
  if (input.action === "nutrition")
    return {
      analysisId: input.requestId,
      needsClarification: false,
      question: "",
      items: [
        {
          name: "אורז לבן מבושל",
          quantity: 150,
          quantityLow: 100,
          quantityHigh: 200,
          basis: "g",
          source: "usda",
          assumption: "כמות ניתנת לתיקון",
          per100: { kcal: 130, protein: 2.7, carbs: 28.2, fat: 0.3 },
        },
      ],
    };
  if (input.action === "history") return { versions: [] };
  return { applied: true };
}
Object.assign(window, {
  wellnessFixture: {
    calls,
    clear: () => {
      calls.length = 0;
    },
  },
});

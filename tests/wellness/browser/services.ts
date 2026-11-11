import { prepareImage } from "../../../src/lib/health/api";
import { applyFoodCorrection } from "../../../supabase/functions/_shared/wellness-food-correction";
import { create } from "zustand";
import { profileSchema, payloadSchemas } from "../../../src/lib/health/model";
import {
  makeProgram,
  parsePreferences,
} from "../../../supabase/functions/_shared/wellness-core";
const calls: { action: string; table?: string; diary?: boolean }[] = [];
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
  loading: false,
  error: null,
  conflict: null,
  boot: async () => {},
  flush: async () => {},
  reset: async () => {},
  resolveConflict: async () => {},
  pending: 0,
  data,
  save: async (
    table: string,
    value: unknown,
    existing?: { id: string; version: number },
    id?: string,
  ) => {
    calls.push({ action: "save", table });
    if (table === "meals") {
      payloadSchemas.meals.parse(value);
      if (
        new URLSearchParams(location.search).has("save-retry") &&
        calls.filter((c) => c.table === "meals").length === 1
      )
        throw new Error("indexeddb_failed");
    }
    const row = {
      id: existing?.id ?? id ?? crypto.randomUUID(),
      owner_user_id: useHealthStore.getState().owner,
      version: (existing?.version ?? 0) + 1,
      data: value,
    };
    useHealthStore.setState((s) => ({
      data: {
        ...s.data,
        [table]: [
          ...s.data[table].filter(
            (r: unknown) => (r as { id: string }).id !== row.id,
          ),
          row,
        ],
      },
    }));
    return row;
  },
  remove: async () => {},
  refresh: async () => {},
}));
export const useHealthText = () => (he: string, en: string) =>
  document.documentElement.lang === "he" ? he : en;
export const lookupFood = async (
  _query: string,
  barcode?: string,
  labelOnly?: boolean,
) => {
  calls.push({ action: labelOnly ? "label-lookup" : "food-lookup" });
  return barcode === "12345678"
    ? {
        foods: [
          {
            id: "off:12345678",
            name: "Synthetic packaged food",
            barcode,
            basis: "g",
            source: "openfoodfacts",
            per100: {
              kcal: 250,
              protein: 10,
              carbs: 30,
              fat: 10,
              fiber: null,
              sugar: null,
              saturatedFat: null,
              sodium: 400,
            },
          },
        ],
      }
    : { foods: [], needsLabel: true, name: "" };
};
export const uploadMealImage = async () => {
  if (new URLSearchParams(location.search).has("photo-progress"))
    await new Promise((r) => setTimeout(r, 350));
  return `${useHealthStore.getState().owner}/test.jpg`;
};
export const createClient = () => ({
  storage: {
    from: () => ({
      createSignedUrl: async () => ({ data: { signedUrl: "" } }),
    }),
  },
});
const storedChat = JSON.parse(localStorage.getItem("synthetic-chat") ?? "null");
let chatGeneration = storedChat?.generation ?? crypto.randomUUID(),
  chatUsed = storedChat?.used ?? 0,
  chatTurns: {
    id: string;
    user_text: string;
    answer: unknown;
    shared_diary: boolean;
    created_at: string;
  }[] = storedChat?.turns ?? [];
function persistChat() {
  localStorage.setItem(
    "synthetic-chat",
    JSON.stringify({
      generation: chatGeneration,
      used: chatUsed,
      turns: chatTurns,
    }),
  );
}
let consent = false,
  contributions = 0;
export async function healthFunction(
  name: string,
  input: Record<string, unknown>,
) {
  calls.push({
    action: String(input.action),
    ...(name === "wellness-chat"
      ? { diary: input.includeDiary as boolean }
      : {}),
  });
  if (name === "wellness-chat") {
    if (input.action === "state")
      return {
        generation: chatGeneration,
        version: chatTurns.length,
        used: chatUsed,
        limit: 40,
        available: true,
        turns: chatTurns,
        resetAt: new Date().toISOString(),
      };
    if (input.action === "clear") {
      chatTurns = [];
      chatGeneration = crypto.randomUUID();
      persistChat();
      return { ok: true };
    }
    if (input.action === "send") {
      chatUsed++;
      const answer = {
        reply:
          "בדקו את הכמויות הרשומות. <script>window.chatInjected=true</script>",
        exerciseIds: ["Push_Up"],
        followUps: ["איך לחלק חלבון?"],
        topic: "nutrition",
      };
      chatTurns.push({
        id: String(input.requestId),
        user_text: String(input.message),
        answer,
        shared_diary: input.includeDiary === true,
        created_at: new Date().toISOString(),
      });
      persistChat();
      return {
        id: input.requestId,
        answer,
        version: chatTurns.length,
        generation: chatGeneration,
      };
    }
  }
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
  if (input.action === "capabilities") {
    if (
      new URLSearchParams(location.search).has("capability-retry") &&
      calls.filter((c) => c.action === "capabilities").length === 1
    )
      return { available: false, serviceReady: true };
    return {
      available: !new URLSearchParams(location.search).has("ai-off"),
      serviceReady: true,
    };
  }
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
  if (input.action === "correct_meal") {
    const row = useHealthStore
      .getState()
      .data.meals.find(
        (m: unknown) => (m as { id: string }).id === input.mealId,
      ) as { data: { items: { food: Record<string, unknown> }[] } };
    if (String(input.description).includes("מיונז"))
      return {
        mealId: input.mealId,
        expectedVersion: input.expectedVersion,
        items: applyFoodCorrection(
          {
            changes: [],
            additions: [
              {
                mentionedText: "מיונז",
                name: "מיונז",
                basis: "g",
                quantity: 15,
                quantityLow: 15,
                quantityHigh: 15,
                per100: { kcal: 680, protein: 1, carbs: 1, fat: 74 },
                assumption: "לפי התיקון שלך",
              },
            ],
          },
          row.data.items,
          String(input.description),
        ),
      };
    return {
      mealId: input.mealId,
      expectedVersion: input.expectedVersion,
      items: row.data.items.map((i) => ({
        ...i,
        food: { ...i.food, name: "דג", source: "ai" },
      })),
    };
  }
  if (input.action === "nutrition") {
    if (new URLSearchParams(location.search).has("photo-progress"))
      await new Promise((r) => setTimeout(r, 1800));
    if (new URLSearchParams(location.search).has("photo-empty"))
      return {
        analysisId: input.requestId,
        items: [],
        needsClarification: false,
        question: "",
      };
    if (
      new URLSearchParams(location.search).has("photo-retry") &&
      calls.filter((c) => c.action === "nutrition").length === 1
    )
      throw new Error("temporary_failure");
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
  }
  if (input.action === "history") return { versions: [] };
  return { applied: true };
}
Object.assign(window, {
  wellnessFixture: {
    calls,
    prepareImage,
    meals: () => useHealthStore.getState().data.meals,
    clear: () => {
      calls.length = 0;
    },
  },
});

export const useIdentity = create(() => ({ actingMemberId: "preview-member" }));
export const useAppStore = create(() => ({
  members: {
    "preview-member": {
      display_name: document.documentElement.lang === "he" ? "דנה" : "Dana",
    },
  },
}));
if (new URLSearchParams(location.search).has("preview")) {
  const today = new Date().toISOString().slice(0, 10);
  data.nutrition_goals = [
    {
      id: crypto.randomUUID(),
      version: 1,
      data: {
        date: today,
        kcal: 2000,
        protein: 100,
        carbs: 250,
        fat: 65,
        method: "manual",
      },
    },
  ];
  data.workout_plans = [
    {
      id: crypto.randomUUID(),
      version: 1,
      data: makeProgram(
        {
          plans: [
            {
              name:
                document.documentElement.lang === "he"
                  ? "יום 1 — כל הגוף"
                  : "Day 1 — Full Body",
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
        parsePreferences({
          goal: "muscle",
          experience: "beginner",
          days: [0, 2, 4],
          minutes: 45,
          split: "full_body",
          focus: [],
          equipment: ["bodyweight", "dumbbell"],
          avoid: [],
          notes: "",
        }),
        today,
      ).changes[0].data,
    },
  ];
}

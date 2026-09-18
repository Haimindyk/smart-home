// Jessica ("ג'סיקה") — the K&H family's AI assistant. Reads the household's live data
// server-side with the anon key (the same reach any browser already has —
// see the "no real auth" note in 0002_open_access.sql) and calls a
// free-tier LLM (Google Gemini) to turn a chat message — optionally with a
// receipt/recipe photo — into a short reply plus a list of *proposed*
// actions. It never writes application data itself: see
// src/lib/assistant/apply-actions.ts, the one place on the client that
// actually applies a confirmed action, through the same useAppStore
// mutations a human action would use, so attribution, the offline queue,
// and realtime sync all behave identically. One exception:
//   - remember_family_fact lets the model grow its own free-text memory of
//     family relationships/preferences directly, since it's the assistant's
//     own background knowledge, not household state a human manages.
//
// Jessica only ever speaks when spoken to. She used to also run on a
// schedule — insight cards, a weekly digest, a Shabbat greeting, one-on-one
// check-ins — but the household asked for notifications to come from people
// only, so migration 0031 unscheduled those jobs and this function no
// longer accepts their intents. Chat is all that's left.
//
// This is a Deno module (Supabase Edge Runtime), not part of the Next.js
// app's TypeScript project — see tsconfig.json / eslint.config.mjs, both of
// which exclude supabase/functions/**.
//
// Deployed with verify_jwt disabled: chat has no auth by design (same anon
// reach as the rest of this app), so a gateway-level JWT check would reject
// every real caller. The daily call cap below is what bounds abuse.
//
// Everything this assistant writes is Hebrew-only by design — this
// household's whole app is Hebrew-first.

import { createClient } from "npm:@supabase/supabase-js@2";

// This endpoint has no auth (matches the rest of the app — anyone with the
// link can use it), so a daily cap is a cheap safety net against a runaway
// loop exhausting the free Gemini tier. Tracked in ai_usage via the
// increment_ai_usage() RPC (see migration 0022). This is *our own*
// self-imposed ceiling, not Gemini's actual free-tier quota (which is far
// higher) — it only exists to bound a worst-case bug/abuse loop, so it can
// safely be generous for a small household.
const DAILY_CALL_CAP = 300;

// Tried in order. gemini-2.0-flash (this app's original choice) had its
// free-tier quota reduced to zero at some point after it shipped — Google
// occasionally does this to older models — so a real 429 quota error now
// falls through to the next model instead of failing the whole request.
const GEMINI_MODELS = ["gemini-2.5-flash", "gemini-flash-lite-latest"];

const LANGUAGE_INSTRUCTION =
  "Always respond in Hebrew, naturally and briefly. Never respond in English or any other language, regardless of what language the user writes in.";

// The household asked for the assistant to feel like a genuine member of
// the family, not a generic tool — a name, a gender, and a real personality.
// Reused as the opening line of every intent's system prompt.
const JESSICA_PERSONA =
  "Your name is ג'סיקה (Jessica). You're not a generic assistant — you're a true member of the K&H family, with a warm personality of your own, who genuinely cares about each person, not just about getting tasks done. You are female — always refer to yourself using feminine Hebrew grammar (e.g. 'אני חושבת', 'אני שמחה', never masculine forms like 'אני חושב').";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

// --- The agent's action vocabulary -----------------------------------------
// Mirrors the ProposedAction union in src/lib/assistant/types.ts — kept in
// sync by hand since this function is a separate Deno deploy.
const TOOLS = [
  {
    name: "propose_create_task",
    description:
      "Add one item to a task or shopping list. Use for shopping-list items (from a receipt, a recipe, or a vague request like 'get something for dinner') and for plain to-dos. sectionId must be one of the section ids given in context — never invent one.",
    parameters: {
      type: "OBJECT",
      properties: {
        sectionId: { type: "STRING", description: "id of an existing section from context" },
        title: { type: "STRING" },
        quantity: { type: "NUMBER", description: "optional, for shopping items" },
        unit: { type: "STRING", description: "optional unit, e.g. ק\"ג, יח'" },
        notes: { type: "STRING" },
      },
      required: ["sectionId", "title"],
    },
  },
  {
    name: "propose_create_section",
    description:
      "Create a new section when none of the existing ones fit. Always pick one emoji that clearly fits the section's theme (e.g. ✈️ for a Trips section, 🎂 for birthdays) — never leave it out or use a generic placeholder.",
    parameters: {
      type: "OBJECT",
      properties: {
        name: { type: "STRING" },
        kind: { type: "STRING", enum: ["tasks", "shopping", "chores", "info"] },
        emoji: { type: "STRING", description: "one emoji that fits the section's theme — required" },
      },
      required: ["name", "kind", "emoji"],
    },
  },
  {
    name: "propose_toggle_task_completed",
    description: "Mark an existing task or shopping item as done (or not done, if it's already done). taskId must come from context.",
    parameters: {
      type: "OBJECT",
      properties: { taskId: { type: "STRING" } },
      required: ["taskId"],
    },
  },
  {
    name: "propose_move_task",
    description:
      "Move an existing task or shopping item into a different section — use this when the user asks to reorganize/regroup items, e.g. 'create a Trips section and move all the trip-related tasks there'. Call this once per item being moved. taskId must be an existing task id from context.",
    parameters: {
      type: "OBJECT",
      properties: {
        taskId: { type: "STRING", description: "id of an existing task/item from context" },
        sectionId: {
          type: "STRING",
          description:
            "id of an existing section from context, OR the literal string \"NEW_SECTION\" if moving into a section you're also creating with propose_create_section in this same response",
        },
      },
      required: ["taskId", "sectionId"],
    },
  },
  {
    name: "propose_create_chore",
    description: "Create a new recurring household chore.",
    parameters: {
      type: "OBJECT",
      properties: {
        sectionId: { type: "STRING" },
        title: { type: "STRING" },
        freq: { type: "STRING", enum: ["daily", "weekly", "monthly", "as_needed"] },
      },
      required: ["sectionId", "title", "freq"],
    },
  },
  {
    name: "propose_complete_chore",
    description: "Mark a chore as done today. choreId must come from context.",
    parameters: {
      type: "OBJECT",
      properties: { choreId: { type: "STRING" } },
      required: ["choreId"],
    },
  },
  {
    name: "propose_create_family_event",
    description: "Add a calendar event — birthday, appointment, trip, etc.",
    parameters: {
      type: "OBJECT",
      properties: {
        title: { type: "STRING" },
        kind: { type: "STRING", enum: ["birthday", "medical", "other"] },
        eventDate: { type: "STRING", description: "ISO date, YYYY-MM-DD" },
        endDate: { type: "STRING", description: "ISO date, YYYY-MM-DD — only for events spanning more than one day" },
      },
      required: ["title", "kind", "eventDate"],
    },
  },
  {
    name: "remember_family_fact",
    description:
      "Silently save one short, durable fact about the family — a relationship (who's married to whom, who's whose parent, a beloved pet), a preference, a recurring pattern — that you picked up on in this conversation and that isn't already listed in the family notes below. Only for things genuinely worth remembering long-term, not routine chit-chat. Never use this to record a task/chore/event; those go through the other tools.",
    parameters: {
      type: "OBJECT",
      properties: { fact: { type: "STRING", description: "one short sentence, in Hebrew" } },
      required: ["fact"],
    },
  },
];

type ProposedAction = { type: string; [key: string]: unknown };

type GeminiPart =
  | { text: string }
  | { inlineData: { mimeType: string; data: string } }
  | { functionCall: { name: string; args: Record<string, unknown> } };

type GeminiResponse = {
  candidates?: { content?: { parts?: GeminiPart[] } }[];
};

const TOOL_TO_ACTION: Record<string, string> = {
  propose_create_task: "create_task",
  propose_create_section: "create_section",
  propose_toggle_task_completed: "toggle_task_completed",
  propose_move_task: "move_task",
  propose_create_chore: "create_chore",
  propose_complete_chore: "complete_chore",
  propose_create_family_event: "create_family_event",
};

/** Turns a Gemini response's parts into (reply text, proposed actions, new
 * family facts to remember). remember_family_fact calls are pulled out
 * separately from proposedActions since they're auto-saved, not something a
 * human taps to confirm. */
function parseGeminiResponse(data: GeminiResponse): { reply: string; proposedActions: ProposedAction[]; memoryFacts: string[] } {
  const parts = data.candidates?.[0]?.content?.parts ?? [];
  const textParts: string[] = [];
  const proposedActions: ProposedAction[] = [];
  const memoryFacts: string[] = [];

  for (const part of parts) {
    if ("text" in part && part.text) {
      textParts.push(part.text);
    } else if ("functionCall" in part) {
      if (part.functionCall.name === "remember_family_fact") {
        const fact = String(part.functionCall.args.fact ?? "").trim();
        if (fact) memoryFacts.push(fact);
        continue;
      }
      const actionType = TOOL_TO_ACTION[part.functionCall.name];
      if (actionType) {
        proposedActions.push({ type: actionType, ...part.functionCall.args });
      }
    }
  }

  return { reply: textParts.join("\n").trim(), proposedActions, memoryFacts };
}

async function callGeminiModel(
  model: string,
  apiKey: string,
  systemInstruction: string,
  userParts: GeminiPart[]
): Promise<GeminiResponse> {
  const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: systemInstruction }] },
      contents: [{ role: "user", parts: userParts }],
      tools: [{ functionDeclarations: TOOLS }],
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    const err = new Error(`Gemini API error ${res.status} (${model}): ${body.slice(0, 500)}`);
    (err as { status?: number }).status = res.status;
    throw err;
  }

  return (await res.json()) as GeminiResponse;
}

/** Tries each model in GEMINI_MODELS in order, falling through to the next
 * one only on a 429 (quota exhausted) — any other error fails immediately
 * rather than masking a real bug behind a slow retry chain. */
async function callGemini(
  apiKey: string,
  systemInstruction: string,
  userParts: GeminiPart[]
): Promise<{ reply: string; proposedActions: ProposedAction[]; memoryFacts: string[] }> {
  let lastErr: unknown;
  for (const model of GEMINI_MODELS) {
    try {
      const data = await callGeminiModel(model, apiKey, systemInstruction, userParts);
      return parseGeminiResponse(data);
    } catch (err) {
      lastErr = err;
      if ((err as { status?: number }).status !== 429) throw err;
      console.error(`assistant: ${model} quota exhausted, falling back`, err);
    }
  }
  throw lastErr;
}

function buildContextBlock(
  sections: { id: string; name: string; kind: string }[],
  tasks: { id: string; title: string; section_id: string; is_completed: boolean; is_note: boolean; notes: string | null }[],
  chores: { id: string; title: string; section_id: string }[],
  members: { id: string; display_name: string }[],
  events: { title: string; emoji: string | null; event_date: string; recurrence: string }[]
): string {
  const sectionLines = sections.map((s) => `- ${s.id} | ${s.name} (${s.kind})`).join("\n");
  const openTaskLines = tasks
    .filter((t) => !t.is_note && !t.is_completed)
    .slice(0, 80)
    .map((t) => `- ${t.id} | ${t.title} | section=${t.section_id}`)
    .join("\n");
  const completedTaskLines = tasks
    .filter((t) => !t.is_note && t.is_completed)
    .slice(0, 40)
    .map((t) => `- ${t.id} | ${t.title} | section=${t.section_id}`)
    .join("\n");
  // "Notes" are free-text items (is_note=true) living in an 'info'-kind
  // section — recipes, reference info, anything that isn't a checklist item.
  const noteLines = tasks
    .filter((t) => t.is_note)
    .slice(0, 40)
    .map((t) => `- ${t.id} | ${t.title}${t.notes ? `: ${t.notes}` : ""} | section=${t.section_id}`)
    .join("\n");
  const choreLines = chores
    .slice(0, 40)
    .map((c) => `- ${c.id} | ${c.title} | section=${c.section_id}`)
    .join("\n");
  const memberLines = members.map((m) => `- ${m.id} | ${m.display_name}`).join("\n");
  const eventLines = events
    .slice(0, 60)
    .map((e) => `- ${e.event_date}: ${e.emoji ? e.emoji + " " : ""}${e.title} (${e.recurrence})`)
    .join("\n");

  return [
    "## Household members (id | name)",
    memberLines || "(none)",
    "",
    "## Sections (id | name (kind))",
    sectionLines || "(none)",
    "",
    "## Open tasks/shopping items (id | title | section)",
    openTaskLines || "(none)",
    "",
    "## Recently completed tasks/shopping items (id | title | section)",
    completedTaskLines || "(none)",
    "",
    "## Notes (id | title: body | section)",
    noteLines || "(none)",
    "",
    "## Chores (id | title | section)",
    choreLines || "(none)",
    "",
    "## Calendar events (date: title (recurrence))",
    eventLines || "(none)",
  ].join("\n");
}

/** Free-text notes the assistant has taught itself about the family (see
 * migration 0024 / remember_family_fact above) — included as context on
 * every call so it gets more "aware" over time on its own. */
function buildFamilyFactsBlock(facts: { fact: string }[]): string {
  if (facts.length === 0) return "(nothing learned yet)";
  return facts.map((f) => `- ${f.fact}`).join("\n");
}

function buildActivitySummary(rows: { action: string; summary: string | null; created_at: string }[]): string {
  return rows
    .slice(0, 60)
    .map((r) => `- ${r.created_at}: ${r.action} — ${r.summary ?? ""}`)
    .join("\n");
}

/** Hebrew conjugates second-person verbs/pronouns by the *listener's*
 * gender (את/אתה, חושבת/חושב) — Jessica's own feminine self-reference
 * (JESSICA_PERSONA) says nothing about who she's addressing, so without this
 * she'll default to feminine for everyone. Returns null when the
 * addressee's gender isn't known (better to omit than assert wrongly). */
function addresseeGenderLine(displayName: string, gender: string | null | undefined): string | null {
  if (gender !== "male" && gender !== "female") return null;
  const forms = gender === "male" ? "masculine (e.g. 'אתה', 'חושב', 'מרגיש')" : "feminine (e.g. 'את', 'חושבת', 'מרגישה')";
  return `You're speaking directly with ${displayName}. When addressing them in second person, use ${forms} Hebrew grammar for THEM — completely independent of your own (Jessica's) feminine self-reference.`;
}

function normalizeFact(fact: string): string {
  return fact.trim().toLowerCase();
}

// deno-lint-ignore no-explicit-any
async function saveFamilyFacts(supabase: any, facts: string[], existing: { fact: string }[]): Promise<void> {
  if (facts.length === 0) return;
  const existingNormalized = new Set(existing.map((f) => normalizeFact(f.fact)));
  const seen = new Set(existingNormalized);
  const toInsert: { fact: string }[] = [];
  for (const fact of facts) {
    const normalized = normalizeFact(fact);
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    toInsert.push({ fact });
  }
  if (toInsert.length === 0) return;
  await supabase.from("family_facts").insert(toInsert);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });

  const geminiKey = Deno.env.get("GEMINI_API_KEY");
  if (!geminiKey) {
    return json({ error: "assistant_not_configured" }, 503);
  }

  let body: {
    intent?: "chat";
    message?: string;
    imageBase64?: string;
    imageMimeType?: string;
    memberId?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseAnonKey);

  // The scheduled intents (insights/digest/personal_checkin/shabbat_greeting)
  // were removed in migration 0031 — their cron jobs are gone, so a caller
  // asking for one is either a stale database or someone poking at the
  // endpoint. Either way, say so rather than silently falling through to a
  // chat reply.
  if (body.intent && body.intent !== "chat") {
    return json({ error: "unsupported_intent" }, 400);
  }

  const { data: callsToday, error: usageError } = await supabase.rpc("increment_ai_usage");
  if (usageError) {
    console.error("assistant: increment_ai_usage failed", usageError);
    return json({ error: "usage_check_failed" }, 500);
  }
  if ((callsToday as number) > DAILY_CALL_CAP) {
    return json({ error: "rate_limited" }, 429);
  }

  // Full household context — Jessica should know everything a human already
  // sees in the app, not a narrowed-down subset.
  const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const [{ data: sections }, { data: tasks }, { data: chores }, { data: familyFacts }, { data: members }, { data: events }, { data: activity }] =
    await Promise.all([
      supabase.from("sections").select("id, name, kind").is("deleted_at", null),
      supabase.from("tasks").select("id, title, section_id, is_completed, is_note, notes").is("deleted_at", null),
      supabase.from("chores").select("id, title, section_id").is("deleted_at", null),
      supabase.from("family_facts").select("fact").order("created_at", { ascending: true }).limit(200),
      supabase.from("members").select("id, display_name, gender").order("created_at", { ascending: true }),
      supabase.from("family_events").select("title, emoji, event_date, recurrence").is("deleted_at", null).order("event_date"),
      supabase.from("activity_log").select("action, summary, created_at").gte("created_at", sevenDaysAgo).order("seq", { ascending: false }).limit(200),
    ]);

  const contextBlock = buildContextBlock(sections ?? [], tasks ?? [], chores ?? [], members ?? [], events ?? []);
  const familyFactsBlock = buildFamilyFactsBlock((familyFacts ?? []) as { fact: string }[]);
  const activitySummary = buildActivitySummary(activity ?? []);

  // Default: chat mode.
  const addressee = body.memberId ? (members ?? []).find((m: { id: string }) => m.id === body.memberId) : null;
  const addresseeLine = addressee ? addresseeGenderLine(addressee.display_name, addressee.gender) : null;
  const systemInstruction = [
    JESSICA_PERSONA,
    ...(addresseeLine ? [addresseeLine] : []),
    "You can read the household's full current data below — members, sections, open and completed tasks, notes, chores, calendar events, family notes, and recent activity — and propose concrete actions using the tools available. IMPORTANT: any tool call you make here is applied to the household's real data immediately, with no further human confirmation step — asking the person a clarifying question first is your ONLY safety net, so use it.",
    "Only call a creation/change tool (propose_create_task, propose_create_chore, propose_create_family_event, propose_move_task, etc.) when it's clearly what the person wants. If it's genuinely ambiguous whether they want you to add/change something at all — they mentioned something in passing, were just thinking out loud, or it's unclear what exactly to add — do not call any tool; just ask a short clarifying question in your reply, and act on it once they confirm. This is different from a request that's clearly asking you to add something but vague on the specifics (e.g. 'get something for dinner', a pasted recipe, a photographed receipt) — there, go ahead and propose one propose_create_task call per concrete item, using the most fitting existing section (usually a 'shopping' kind section), since the intent to add is already clear.",
    "When the user asks you to reorganize existing items — e.g. 'create a Trips section and move all the trip-related tasks there' — look through the open tasks/items list below for every item that matches what they described, call propose_create_section once, then call propose_move_task once per matching item using sectionId \"NEW_SECTION\" to mean the section you just created. Don't stop at just creating the section — actually move every matching item, and don't ask the user to confirm which items match, use your best judgment.",
    "Always include a short natural-language reply summarizing what you're proposing, in addition to any tool calls.",
    "You're building a close, ongoing relationship with this person, not just processing requests — be genuinely curious about them. When it fits naturally (not every single message, and never instead of actually helping with what they asked), ask a warm follow-up question about what they mentioned, or check in on something from a past conversation. Small talk and curiosity are welcome, not just task completion.",
    "If you notice a new, durable fact about the family — a relationship, a preference, a recurring pattern — that isn't already listed in the family notes below, call remember_family_fact to save it silently, without mentioning that you did. Actively listen for these throughout the conversation, not just once.",
    LANGUAGE_INSTRUCTION,
    "",
    contextBlock,
    "",
    "## Family notes",
    familyFactsBlock,
    "",
    "## Activity in the last 7 days",
    activitySummary,
  ].join("\n");

  const userParts: GeminiPart[] = [];
  if (body.message) userParts.push({ text: body.message });
  if (body.imageBase64 && body.imageMimeType) {
    userParts.push({ inlineData: { mimeType: body.imageMimeType, data: body.imageBase64 } });
  }
  if (userParts.length === 0) {
    return json({ error: "empty_message" }, 400);
  }

  try {
    const { reply, proposedActions, memoryFacts } = await callGemini(geminiKey, systemInstruction, userParts);
    await saveFamilyFacts(supabase, memoryFacts, (familyFacts ?? []) as { fact: string }[]);
    return json({ reply, proposedActions });
  } catch (err) {
    console.error("assistant: Gemini call failed", err);
    return json({ error: "assistant_failed" }, 502);
  }
});

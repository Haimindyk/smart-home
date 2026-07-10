// The K&H AI assistant ("העוזר"). Reads the household's live data
// server-side with the anon key (the same reach any browser already has —
// see the "no real auth" note in 0002_open_access.sql) and calls a
// free-tier LLM (Google Gemini) to turn a chat message — optionally with a
// receipt/recipe photo — into a short reply plus a list of *proposed*
// actions. It never writes application data itself: see
// src/lib/assistant/apply-actions.ts, the one place on the client that
// actually applies a confirmed action, through the same useAppStore
// mutations a human action would use, so attribution, the offline queue,
// and realtime sync all behave identically. Three exceptions, all
// low-stakes/reversible rather than household-data mutations a human needs
// to confirm:
//   - "insights" mode inserts rows straight into ai_suggestions — those are
//     already just a proposal sitting in an inbox, applied the same way as
//     a chat action once a human taps it. It also now fires a push
//     notification (see migration 0024) so a new suggestion isn't silent.
//   - "joke" mode writes a broadcast message straight to activity_log once a
//     day — a pure FYI with nothing to "apply", riding the existing
//     broadcast -> push pipeline.
//   - "digest" mode does the same once a week, summarizing the week ahead
//     (upcoming events/due tasks, chores coming due).
//   - remember_family_fact (a tool available in every intent) lets the model
//     grow its own free-text memory of family relationships/preferences
//     directly, since it's the assistant's own background knowledge, not
//     household state a human manages.
//
// This is a Deno module (Supabase Edge Runtime), not part of the Next.js
// app's TypeScript project — see tsconfig.json / eslint.config.mjs, both of
// which exclude supabase/functions/**.
//
// Deployed with verify_jwt disabled: chat has no auth by design (same anon
// reach as the rest of this app), and the insights/joke intents use their
// own shared-secret check (verify_assistant_trigger_secret) rather than a
// Supabase-issued JWT — the pg_cron jobs' net.http_post calls send a random
// Vault secret as the bearer token, not a JWT, so gateway-level verify_jwt
// would reject them before this code ever ran.
//
// Everything this assistant writes (chat replies, insight notes, jokes) is
// Hebrew-only by design — this household's whole app is Hebrew-first.

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
    name: "propose_send_broadcast",
    description: "Draft a broadcast message to the whole household (e.g. a reply to something someone asked).",
    parameters: {
      type: "OBJECT",
      properties: { message: { type: "STRING" } },
      required: ["message"],
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
  propose_send_broadcast: "send_broadcast",
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
  tasks: { id: string; title: string; section_id: string; is_completed: boolean }[],
  chores: { id: string; title: string; section_id: string }[]
): string {
  const sectionLines = sections.map((s) => `- ${s.id} | ${s.name} (${s.kind})`).join("\n");
  const openTaskLines = tasks
    .filter((t) => !t.is_completed)
    .slice(0, 80)
    .map((t) => `- ${t.id} | ${t.title} | section=${t.section_id}`)
    .join("\n");
  const choreLines = chores
    .slice(0, 40)
    .map((c) => `- ${c.id} | ${c.title} | section=${c.section_id}`)
    .join("\n");

  return [
    "## Sections (id | name (kind))",
    sectionLines || "(none)",
    "",
    "## Open tasks/shopping items (id | title | section)",
    openTaskLines || "(none)",
    "",
    "## Chores (id | title | section)",
    choreLines || "(none)",
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

/** "2026-07-10" -> Israel-local date string N days later, same shape. */
function addDaysStr(dateStr: string, days: number): string {
  const [y, m, d] = dateStr.split("-").map(Number);
  const next = new Date(Date.UTC(y, m - 1, d + days));
  return `${next.getUTCFullYear()}-${String(next.getUTCMonth() + 1).padStart(2, "0")}-${String(next.getUTCDate()).padStart(2, "0")}`;
}

function toIsraelDateStr(iso: string): string {
  return new Date(iso).toLocaleDateString("en-CA", { timeZone: "Asia/Jerusalem" });
}

/** Rolls a yearly-recurring event's month/day forward to its next
 * occurrence on/after `todayStr` — a light JS mirror of the
 * family_event_next_occurrence SQL function (see migration 0010), close
 * enough for "is this in the next 7 days" filtering. */
function nextYearlyOccurrence(eventDateStr: string, todayStr: string): string {
  const [, m, d] = eventDateStr.split("-");
  const [todayYear] = todayStr.split("-");
  let candidate = `${todayYear}-${m}-${d}`;
  if (candidate < todayStr) candidate = `${Number(todayYear) + 1}-${m}-${d}`;
  return candidate;
}

function getBearerToken(req: Request): string | null {
  const header = req.headers.get("Authorization") ?? req.headers.get("authorization");
  if (!header?.startsWith("Bearer ")) return null;
  const token = header.slice("Bearer ".length).trim();
  return token.length > 0 ? token : null;
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
    intent?: "chat" | "insights" | "joke" | "digest";
    message?: string;
    imageBase64?: string;
    imageMimeType?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseAnonKey);

  // The insights sweep, the daily joke, and the weekly digest all write
  // straight into everyone's dashboard/feed (unlike chat, which only a
  // human can act on) — gate them with a shared secret so an open endpoint
  // can't be used to spam the household. Chat stays open to anyone with
  // the link, same as the rest of the app.
  if (body.intent === "insights" || body.intent === "joke" || body.intent === "digest") {
    const secret = getBearerToken(req);
    const { data: valid } = secret
      ? await supabase.rpc("verify_assistant_trigger_secret", { p_secret: secret })
      : { data: false };
    if (!valid) return json({ error: "unauthorized" }, 401);
  }

  const { data: callsToday, error: usageError } = await supabase.rpc("increment_ai_usage");
  if (usageError) {
    console.error("assistant: increment_ai_usage failed", usageError);
    return json({ error: "usage_check_failed" }, 500);
  }
  if ((callsToday as number) > DAILY_CALL_CAP) {
    return json({ error: "rate_limited" }, 429);
  }

  const [{ data: sections }, { data: tasks }, { data: chores }, { data: familyFacts }] = await Promise.all([
    supabase.from("sections").select("id, name, kind").is("deleted_at", null),
    supabase.from("tasks").select("id, title, section_id, is_completed").is("deleted_at", null).eq("is_note", false),
    supabase.from("chores").select("id, title, section_id").is("deleted_at", null),
    supabase.from("family_facts").select("fact").order("created_at", { ascending: true }).limit(200),
  ]);

  const contextBlock = buildContextBlock(sections ?? [], tasks ?? [], chores ?? []);
  const familyFactsBlock = buildFamilyFactsBlock((familyFacts ?? []) as { fact: string }[]);

  if (body.intent === "joke") {
    const { data: assistantMember } = await supabase
      .from("members")
      .select("id")
      .eq("email", "assistant@kh.family")
      .maybeSingle();
    const assistantId = (assistantMember as { id: string } | null)?.id ?? null;

    if (assistantId) {
      const startOfDay = new Date();
      startOfDay.setUTCHours(0, 0, 0, 0);
      const { data: existing } = await supabase
        .from("activity_log")
        .select("id")
        .eq("actor_id", assistantId)
        .eq("entity_type", "broadcast")
        .gte("created_at", startOfDay.toISOString())
        .limit(1);
      if (existing && existing.length > 0) {
        return json({ sent: false, reason: "already_sent_today" });
      }
    }

    const systemInstruction = [
      "You are 'העוזר', the household AI embedded in the K&H family organizer app.",
      "Write exactly one short, warm, funny family-friendly joke for the household. You may (but don't have to) reference the family notes below — e.g. Louis the dog.",
      "Do not call any tools. Reply with just the joke text — no preamble, no quotation marks.",
      LANGUAGE_INSTRUCTION,
      "",
      "## Family notes",
      familyFactsBlock,
    ].join("\n");

    const { reply, memoryFacts } = await callGemini(geminiKey, systemInstruction, [
      { text: "תן לי בדיחה חמה ומצחיקה למשפחה." },
    ]);
    await saveFamilyFacts(supabase, memoryFacts, (familyFacts ?? []) as { fact: string }[]);

    const jokeText = reply.trim();
    if (!jokeText) return json({ sent: false, reason: "empty" });

    await supabase.from("activity_log").insert({
      entity_type: "broadcast",
      entity_id: crypto.randomUUID(),
      action: "message",
      actor_id: assistantId,
      summary: `😄 ${jokeText}`,
    });

    return json({ sent: true });
  }

  if (body.intent === "digest") {
    const { data: assistantMember } = await supabase
      .from("members")
      .select("id")
      .eq("email", "assistant@kh.family")
      .maybeSingle();
    const assistantId = (assistantMember as { id: string } | null)?.id ?? null;

    // A digest is once-a-week; guard against a double-fire the same way the
    // daily joke guards against firing twice in a day, just with a wider
    // window, and a marker prefix so a joke sent earlier the same week
    // doesn't count as "already sent a digest".
    if (assistantId) {
      const sixDaysAgo = new Date(Date.now() - 6 * 24 * 60 * 60 * 1000);
      const { data: existing } = await supabase
        .from("activity_log")
        .select("id, summary")
        .eq("actor_id", assistantId)
        .eq("entity_type", "broadcast")
        .gte("created_at", sixDaysAgo.toISOString())
        .ilike("summary", "🗓️%")
        .limit(1);
      if (existing && existing.length > 0) {
        return json({ sent: false, reason: "already_sent_this_week" });
      }
    }

    const todayStr = toIsraelDateStr(new Date().toISOString());
    const weekAheadStr = addDaysStr(todayStr, 7);

    const [{ data: events }, { data: dueTasks }, { data: dueChores }] = await Promise.all([
      supabase.from("family_events").select("title, emoji, event_date, recurrence").is("deleted_at", null),
      supabase
        .from("tasks")
        .select("title, due_at")
        .is("deleted_at", null)
        .eq("is_note", false)
        .eq("is_completed", false)
        .not("due_at", "is", null),
      supabase.from("chores").select("title, next_due_at").is("deleted_at", null),
    ]);

    const upcomingEventLines = (events ?? [])
      .map((e: { title: string; emoji: string | null; event_date: string; recurrence: string }) => ({
        ...e,
        next: e.recurrence === "yearly" ? nextYearlyOccurrence(e.event_date, todayStr) : e.event_date,
      }))
      .filter((e) => e.next >= todayStr && e.next <= weekAheadStr)
      .sort((a, b) => a.next.localeCompare(b.next))
      .map((e) => `- ${e.next}: ${e.emoji ? e.emoji + " " : ""}${e.title}`);

    const dueTaskLines = (dueTasks ?? [])
      .map((t: { title: string; due_at: string }) => ({ title: t.title, date: toIsraelDateStr(t.due_at) }))
      .filter((t) => t.date <= weekAheadStr)
      .sort((a, b) => a.date.localeCompare(b.date))
      .map((t) => `- ${t.date}: ${t.title}`);

    const dueChoreLines = (dueChores ?? [])
      .map((c: { title: string; next_due_at: string }) => ({ title: c.title, date: toIsraelDateStr(c.next_due_at) }))
      .filter((c) => c.date <= weekAheadStr)
      .sort((a, b) => a.date.localeCompare(b.date))
      .map((c) => `- ${c.date}: ${c.title}`);

    if (upcomingEventLines.length === 0 && dueTaskLines.length === 0 && dueChoreLines.length === 0) {
      return json({ sent: false, reason: "nothing_this_week" });
    }

    const systemInstruction = [
      "You are 'העוזר', the household AI embedded in the K&H family organizer app.",
      "Write a short, warm, genuinely funny weekly recap for the household — a few sentences covering what's coming up this week from the lists below (events, due tasks/appointments, chores coming due). Keep the same playful personality as the household's daily joke, not a dry status report.",
      "Only mention things actually in the lists below — never invent dates or items. If a list is empty, just don't mention that category.",
      "Do not call any tools. Reply with just the recap text — no preamble, no markdown, no bullet points; write it as natural prose a person would text to their family group chat.",
      LANGUAGE_INSTRUCTION,
      "",
      "## Events this week",
      upcomingEventLines.join("\n") || "(none)",
      "",
      "## Tasks/appointments due this week",
      dueTaskLines.join("\n") || "(none)",
      "",
      "## Chores coming due this week",
      dueChoreLines.join("\n") || "(none)",
    ].join("\n");

    const { reply, memoryFacts } = await callGemini(geminiKey, systemInstruction, [
      { text: "תכתוב לי סיכום שבועי חם ומצחיק למשפחה, על סמך הרשימות." },
    ]);
    await saveFamilyFacts(supabase, memoryFacts, (familyFacts ?? []) as { fact: string }[]);

    const digestText = reply.trim();
    if (!digestText) return json({ sent: false, reason: "empty" });

    await supabase.from("activity_log").insert({
      entity_type: "broadcast",
      entity_id: crypto.randomUUID(),
      action: "message",
      actor_id: assistantId,
      summary: `🗓️ ${digestText}`,
    });

    return json({ sent: true });
  }

  if (body.intent === "insights") {
    const since = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
    const { data: activity } = await supabase
      .from("activity_log")
      .select("action, summary, created_at")
      .gte("created_at", since)
      .order("seq", { ascending: false })
      .limit(200);

    const systemInstruction = [
      "You are the K&H family household assistant. Look at the recent activity log and the current open tasks/chores below, and see if there's a genuinely useful, gentle observation worth surfacing as a dashboard suggestion — e.g. a chore nobody's done in a while, or a shopping item that keeps coming back.",
      "Propose AT MOST ONE suggestion. If nothing is clearly worth surfacing, propose nothing and just reply with an empty string.",
      "Phrase the suggestion with the same warm, genuinely funny personality as the household's daily joke — a light pun or a playful nudge — instead of a dry notification. Never nag about something already handled; the humor should serve the message, not replace it, and it must still be tied to a real, specific observation.",
      "If you notice a new, durable fact about the family that isn't already listed in the family notes below, call remember_family_fact to save it.",
      LANGUAGE_INSTRUCTION,
      "",
      contextBlock,
      "",
      "## Family notes",
      familyFactsBlock,
      "",
      "## Activity in the last 7 days",
      buildActivitySummary(activity ?? []),
    ].join("\n");

    const { reply, proposedActions, memoryFacts } = await callGemini(geminiKey, systemInstruction, [
      { text: "Look at the household's recent activity and suggest at most one useful action, if any." },
    ]);
    await saveFamilyFacts(supabase, memoryFacts, (familyFacts ?? []) as { fact: string }[]);

    if (proposedActions.length > 0 && reply) {
      const action = proposedActions[0];
      await supabase.from("ai_suggestions").insert({
        summary: reply,
        emoji: "💡",
        action,
      });
    }

    return json({ inserted: proposedActions.length > 0 });
  }

  // Default: chat mode.
  const systemInstruction = [
    "You are 'העוזר' (the assistant), a helpful household AI embedded in the K&H family organizer app.",
    "You can read the household's current sections, open tasks, and chores (given below) and propose concrete actions using the tools available — you never apply anything yourself, a human always confirms.",
    "When resolving a vague request (e.g. 'get something for dinner') or a pasted recipe or a photographed receipt, propose one propose_create_task call per concrete item, using the most fitting existing section (usually a 'shopping' kind section).",
    "When the user asks you to reorganize existing items — e.g. 'create a Trips section and move all the trip-related tasks there' — look through the open tasks/items list below for every item that matches what they described, call propose_create_section once, then call propose_move_task once per matching item using sectionId \"NEW_SECTION\" to mean the section you just created. Don't stop at just creating the section — actually move every matching item, and don't ask the user to confirm which items match, use your best judgment.",
    "Always include a short natural-language reply summarizing what you're proposing, in addition to any tool calls.",
    "If you notice a new, durable fact about the family — a relationship, a preference, a recurring pattern — that isn't already listed in the family notes below, call remember_family_fact to save it silently, without mentioning that you did.",
    LANGUAGE_INSTRUCTION,
    "",
    contextBlock,
    "",
    "## Family notes",
    familyFactsBlock,
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

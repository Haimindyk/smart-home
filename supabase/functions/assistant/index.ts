// The K&H AI assistant ("העוזר"). Reads the household's live data
// server-side with the anon key (the same reach any browser already has —
// see the "no real auth" note in 0002_open_access.sql) and calls a
// free-tier LLM (Google Gemini) to turn a chat message — optionally with a
// receipt/recipe photo — into a short reply plus a list of *proposed*
// actions. It never writes application data itself: see
// src/lib/assistant/apply-actions.ts, the one place on the client that
// actually applies a confirmed action, through the same useAppStore
// mutations a human action would use, so attribution, the offline queue,
// and realtime sync all behave identically. The one exception is "insights"
// mode, which inserts rows straight into ai_suggestions — those are already
// just a proposal sitting in an inbox, applied the same way as a chat action
// once a human taps it.
//
// This is a Deno module (Supabase Edge Runtime), not part of the Next.js
// app's TypeScript project — see tsconfig.json / eslint.config.mjs, both of
// which exclude supabase/functions/**.

import { createClient } from "npm:@supabase/supabase-js@2";

// This endpoint has no auth (matches the rest of the app — anyone with the
// link can use it), so a modest daily cap is a cheap safety net against a
// runaway loop exhausting the free Gemini tier. Tracked in ai_usage via the
// increment_ai_usage() RPC (see migration 0022).
const DAILY_CALL_CAP = 50;
const GEMINI_MODEL = "gemini-2.0-flash";

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
    description: "Create a new section when none of the existing ones fit (rare).",
    parameters: {
      type: "OBJECT",
      properties: {
        name: { type: "STRING" },
        kind: { type: "STRING", enum: ["tasks", "shopping", "chores", "info"] },
        emoji: { type: "STRING" },
      },
      required: ["name", "kind"],
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
  propose_create_chore: "create_chore",
  propose_complete_chore: "complete_chore",
  propose_create_family_event: "create_family_event",
  propose_send_broadcast: "send_broadcast",
};

/** Turns a Gemini response's parts into (reply text, proposed actions). */
function parseGeminiResponse(data: GeminiResponse): { reply: string; proposedActions: ProposedAction[] } {
  const parts = data.candidates?.[0]?.content?.parts ?? [];
  const textParts: string[] = [];
  const proposedActions: ProposedAction[] = [];

  for (const part of parts) {
    if ("text" in part && part.text) {
      textParts.push(part.text);
    } else if ("functionCall" in part) {
      const actionType = TOOL_TO_ACTION[part.functionCall.name];
      if (actionType) {
        proposedActions.push({ type: actionType, ...part.functionCall.args });
      }
    }
  }

  return { reply: textParts.join("\n").trim(), proposedActions };
}

async function callGemini(
  apiKey: string,
  systemInstruction: string,
  userParts: GeminiPart[]
): Promise<{ reply: string; proposedActions: ProposedAction[] }> {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: systemInstruction }] },
        contents: [{ role: "user", parts: userParts }],
        tools: [{ functionDeclarations: TOOLS }],
      }),
    }
  );

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Gemini API error ${res.status}: ${body.slice(0, 500)}`);
  }

  const data = (await res.json()) as GeminiResponse;
  return parseGeminiResponse(data);
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

function buildActivitySummary(rows: { action: string; summary: string | null; created_at: string }[]): string {
  return rows
    .slice(0, 60)
    .map((r) => `- ${r.created_at}: ${r.action} — ${r.summary ?? ""}`)
    .join("\n");
}

function getBearerToken(req: Request): string | null {
  const header = req.headers.get("Authorization") ?? req.headers.get("authorization");
  if (!header?.startsWith("Bearer ")) return null;
  const token = header.slice("Bearer ".length).trim();
  return token.length > 0 ? token : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });

  const geminiKey = Deno.env.get("GEMINI_API_KEY");
  if (!geminiKey) {
    return json({ error: "assistant_not_configured" }, 503);
  }

  let body: {
    intent?: "chat" | "insights";
    message?: string;
    imageBase64?: string;
    imageMimeType?: string;
    locale?: "he" | "en";
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseAnonKey);

  // The insights sweep writes straight into everyone's dashboard (unlike
  // chat, which only a human can act on) — gate it with a shared secret so
  // an open endpoint can't be used to spam the household with junk cards.
  // Chat stays open to anyone with the link, same as the rest of the app.
  if (body.intent === "insights") {
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

  const locale = body.locale === "en" ? "en" : "he";
  const languageInstruction =
    locale === "he" ? "Respond in Hebrew, naturally and briefly." : "Respond in English, naturally and briefly.";

  const [{ data: sections }, { data: tasks }, { data: chores }] = await Promise.all([
    supabase.from("sections").select("id, name, kind").is("deleted_at", null),
    supabase.from("tasks").select("id, title, section_id, is_completed").is("deleted_at", null).eq("is_note", false),
    supabase.from("chores").select("id, title, section_id").is("deleted_at", null),
  ]);

  const contextBlock = buildContextBlock(sections ?? [], tasks ?? [], chores ?? []);

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
      "Never nag about something already handled. Keep the tone warm, not naggy.",
      languageInstruction,
      "",
      contextBlock,
      "",
      "## Activity in the last 7 days",
      buildActivitySummary(activity ?? []),
    ].join("\n");

    const { reply, proposedActions } = await callGemini(geminiKey, systemInstruction, [
      { text: "Look at the household's recent activity and suggest at most one useful action, if any." },
    ]);

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
    "Always include a short natural-language reply summarizing what you're proposing, in addition to any tool calls.",
    languageInstruction,
    "",
    contextBlock,
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
    const { reply, proposedActions } = await callGemini(geminiKey, systemInstruction, userParts);
    return json({ reply, proposedActions });
  } catch (err) {
    console.error("assistant: Gemini call failed", err);
    return json({ error: "assistant_failed" }, 502);
  }
});

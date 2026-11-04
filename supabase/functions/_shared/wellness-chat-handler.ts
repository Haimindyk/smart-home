import { body, cors, json, failure, requireUser } from "./health-http.ts";
import {
  configured,
  createProvider,
  type Environment,
} from "./wellness-provider.ts";
import { adult, record } from "./wellness-core.ts";
import {
  chatMessage,
  chatVersion,
  parseChatAnswer,
  historyForModel,
  diarySummary,
  CHAT_SYSTEM,
  type ChatTurn,
} from "./wellness-chat-core.ts";
import { wellnessExercises } from "./exercise-catalog.ts";
const uuid = (v: unknown) => {
  if (
    typeof v !== "string" ||
    !/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(
      v,
    )
  )
    throw new Error("invalid_input");
  return v;
};
function checked<T>(r: { data: T; error: { message?: string } | null }) {
  if (r.error) {
    for (const code of ["version_conflict", "request_conflict"])
      if (r.error.message?.includes(code)) throw new Error(code);
    throw new Error("failed");
  }
  return r.data;
}
export async function handleChat(req: Request, env: Environment) {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  let job: {
    admin: Awaited<ReturnType<typeof requireUser>>["admin"];
    owner: string;
    id: string;
  } | null = null;
  try {
    const { admin, user } = await requireUser(req),
      input = record(await body(req));
    const state = checked(
      await admin.rpc("wellness_chat_state", { p_owner: user.id }),
    );
    const turns = () =>
      admin
        .from("wellness_chat_turns")
        .select("id,user_text,answer,shared_diary,created_at")
        .eq("owner_user_id", user.id)
        .eq("generation", state.generation)
        .order("created_at", { ascending: false })
        .order("id")
        .limit(40);
    const available =
      configured(env) && env("WELLNESS_MODEL_SOURCE") !== "owned";
    if (input.action === "state")
      return json({
        ...state,
        turns: checked(await turns())?.reverse() ?? [],
        available,
        resetAt: new Date(
          Date.parse(new Date().toISOString().slice(0, 10)) + 86400000,
        ).toISOString(),
      });
    if (input.action === "clear") {
      checked(await admin.rpc("wellness_chat_clear", { p_owner: user.id }));
      return json({ ok: true });
    }
    if (input.action !== "send") throw new Error("invalid_input");
    if (!available) throw new Error("not_configured");
    const profile = checked(
      await admin
        .from("health_profiles")
        .select("data")
        .eq("owner_user_id", user.id)
        .is("deleted_at", null)
        .maybeSingle(),
    )?.data;
    const today = new Intl.DateTimeFormat("en-CA", {
      timeZone: profile?.timezone ?? "Asia/Jerusalem",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(new Date());
    if (!profile || !adult(profile, today))
      throw new Error("adult_profile_required");
    if (profile.aiProviderConsent !== true) throw new Error("consent_required");
    const message = chatMessage(input.message),
      id = uuid(input.requestId),
      generation = uuid(input.generation),
      version = chatVersion(input.version);
    if (typeof input.includeDiary !== "boolean")
      throw new Error("invalid_input");
    const fingerprint = Array.from(
      new Uint8Array(
        await crypto.subtle.digest(
          "SHA-256",
          new TextEncoder().encode(
            JSON.stringify({
              message,
              generation,
              version,
              includeDiary: input.includeDiary,
            }),
          ),
        ),
      ),
    )
      .map((x) => x.toString(16).padStart(2, "0"))
      .join("");
    const claim = checked(
      await admin.rpc("wellness_chat_claim", {
        p_id: id,
        p_owner: user.id,
        p_generation: generation,
        p_version: version,
        p_fingerprint: fingerprint,
      }),
    );
    if (claim.state === "quota") throw new Error("quota_exhausted");
    if (claim.state === "busy") throw new Error("analysis_busy");
    if (claim.state === "complete") return json(claim.result);
    if (claim.state !== "claimed") throw new Error("failed");
    job = { admin, owner: user.id, id };
    let context: unknown = null;
    if (input.includeDiary) {
      const [meals, goals, sessions] = await Promise.all([
        admin
          .from("meals")
          .select("data")
          .eq("owner_user_id", user.id)
          .eq("data->>date", today)
          .is("deleted_at", null)
          .limit(100),
        admin
          .from("nutrition_goals")
          .select("data")
          .eq("owner_user_id", user.id)
          .lte("data->>date", today)
          .is("deleted_at", null)
          .order("data->>date", { ascending: false })
          .limit(1),
        admin
          .from("workout_sessions")
          .select("data")
          .eq("owner_user_id", user.id)
          .eq("data->>status", "completed")
          .lte("data->>date", today)
          .is("deleted_at", null)
          .order("data->>date", { ascending: false })
          .limit(3),
      ]);
      context = diarySummary(
        today,
        checked(meals) ?? [],
        checked(goals)?.[0]?.data ?? null,
        checked(sessions) ?? [],
      );
    }
    const history = historyForModel(
      (checked(await turns()) ?? []) as ChatTurn[],
    );
    const provider = createProvider(env);
    const answer = parseChatAnswer(
      await provider.structured(
        CHAT_SYSTEM,
        {
          message,
          history,
          diary: context,
          catalog: wellnessExercises.map((e) => ({
            id: e.id,
            name: e.he,
            nameEn: e.en,
            muscle: e.muscle,
            equipment: e.equipment,
          })),
        },
        1600,
      ),
    );
    const result = checked(
      await admin.rpc("wellness_chat_publish", {
        p_id: id,
        p_owner: user.id,
        p_generation: generation,
        p_version: version,
        p_message: message,
        p_answer: answer,
        p_diary: input.includeDiary,
      }),
    );
    return json(result);
  } catch (e) {
    const code = e instanceof Error ? e.message : "failed";
    if (job)
      await job.admin
        .from("wellness_ai_jobs")
        .update({
          status: "failed",
          error_code: [
            "invalid_output",
            "provider_failed",
            "rate_limited",
            "version_conflict",
            "request_conflict",
          ].includes(code)
            ? code
            : "failed",
          updated_at: new Date().toISOString(),
        })
        .eq("id", job.id)
        .eq("owner_user_id", job.owner)
        .eq("status", "processing");
    if (
      [
        "version_conflict",
        "request_conflict",
        "quota_exhausted",
        "adult_profile_required",
        "consent_required",
      ].includes(code)
    )
      return json(
        { error: code },
        code === "quota_exhausted"
          ? 429
          : code.endsWith("conflict")
            ? 409
            : 400,
      );
    return failure(e);
  }
}

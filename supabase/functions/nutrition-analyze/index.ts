import {
  body,
  cors,
  failure,
  json,
  requireUser,
} from "../_shared/health-http.ts";
import { analyzeImage } from "../_shared/health-gemini.ts";
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  let context: Awaited<ReturnType<typeof requireUser>> | null = null;
  let requestId = "";
  let claimed = false;
  let model = "";
  const start = Date.now();
  try {
    context = await requireUser(req);
    const { admin, user } = context;
    const input = await body(req);
    if (
      typeof input.requestId !== "string" ||
      !/^[0-9a-f-]{36}$/i.test(input.requestId) ||
      !["meal", "label"].includes(input.mode) ||
      typeof input.imagePath !== "string" ||
      !input.imagePath.startsWith(user.id + "/") ||
      input.imagePath.includes("..")
    )
      throw new Error("invalid_input");
    requestId = input.requestId;
    const { data: profile } = await admin
      .from("health_profiles")
      .select("data")
      .eq("owner_user_id", user.id)
      .is("deleted_at", null)
      .maybeSingle();
    if (!profile?.data?.aiConsent) throw new Error("invalid_input");
    const { data: settings } = await admin.rpc("health_service_settings");
    const key = Deno.env.get("GEMINI_API_KEY");
    model = Deno.env.get("NUTRITION_GEMINI_MODEL") ?? settings?.model;
    if (!key || !settings?.enabled || !model) throw new Error("not_configured");
    const { data: claim, error } = await admin.rpc("health_claim_analysis", {
      p_id: requestId,
      p_owner: user.id,
      p_path: input.imagePath,
    });
    if (error) throw new Error("invalid_input");
    if (claim === "busy") throw new Error("analysis_busy");
    if (claim === "complete") {
      const { data } = await admin
        .from("nutrition_analyses")
        .select("result")
        .eq("id", requestId)
        .eq("owner_user_id", user.id)
        .single();
      if (!data) throw new Error("not_found");
      return json({ ...data.result, analysisId: requestId });
    }
    claimed = true;
    const { data: file, error: fileError } = await admin.storage
      .from("health-images")
      .download(input.imagePath);
    if (
      fileError ||
      !file ||
      file.size > 5242880 ||
      !["image/jpeg", "image/png", "image/webp"].includes(file.type)
    )
      throw new Error("invalid_image");
    const { result, tokens } = await analyzeImage(
      key,
      model,
      new Uint8Array(await file.arrayBuffer()),
      file.type,
      input.mode,
      typeof input.description === "string"
        ? input.description.slice(0, 1000)
        : "",
    );
    const enriched = {
      ...result,
      items: result.items.map((i) => ({
        ...i,
        source: input.mode === "label" ? "label" : "ai",
        sourceId: undefined,
      })),
    };
    if (input.mode === "meal" && result.items.length) {
      const names = result.items.map((i) => i.name);
      const { data: matches } = await admin
        .from("food_catalog")
        .select("data")
        .in("data->>name", names);
      for (const item of enriched.items) {
        const match = matches?.find(
          (m) => m.data.name === item.name && m.data.basis === item.basis,
        )?.data;
        if (match) {
          item.per100 = match.per100;
          item.source = match.source;
          item.sourceId = match.sourceId;
        }
      }
    }
    const { error: saveError } = await admin
      .from("nutrition_analyses")
      .update({
        status: "complete",
        result: enriched,
        model,
        updated_at: new Date().toISOString(),
      })
      .eq("id", requestId)
      .eq("owner_user_id", user.id);
    if (saveError) throw new Error("failed");
    await admin.rpc("health_log_ai", {
      p_owner: user.id,
      p_model: model,
      p_elapsed: Date.now() - start,
      p_tokens: tokens,
      p_outcome: "complete",
    });
    return json({ ...enriched, analysisId: requestId });
  } catch (e) {
    if (context && claimed) {
      await context.admin
        .from("nutrition_analyses")
        .update({ status: "failed", updated_at: new Date().toISOString() })
        .eq("id", requestId)
        .eq("owner_user_id", context.user.id);
      await context.admin.rpc("health_log_ai", {
        p_owner: context.user.id,
        p_model: model,
        p_elapsed: Date.now() - start,
        p_tokens: null,
        p_outcome: e instanceof Error ? e.message : "failed",
      });
    }
    return failure(e);
  }
});

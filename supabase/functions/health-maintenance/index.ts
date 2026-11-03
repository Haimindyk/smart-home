import {
  adminClient,
  body,
  cors,
  failure,
  json,
  referencedImages,
} from "../_shared/health-http.ts";
import { analyzeImage } from "../_shared/health-gemini.ts";
import { probeLabelPng } from "../_shared/probe-label.ts";
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const admin = adminClient();
    const token = req.headers.get("x-health-maintenance");
    if (!token) throw new Error("unauthorized");
    const input = await body(req);
    if (typeof input.probe !== "boolean") throw new Error("invalid_input");
    const { data: accepted, error: authError } = await admin.rpc(
      "health_accept_maintenance",
      { p_token: token, p_probe: input.probe },
    );
    if (authError || !accepted) throw new Error("unauthorized");
    const { data: settings, error } = await admin.rpc(
      "health_service_settings",
    );
    if (error) throw new Error("failed");
    if (input.probe) {
      const model = Deno.env.get("NUTRITION_GEMINI_MODEL") ?? settings.model;
      let ok = false;
      let probeError: string | null = null;
      const availableModels: string[] = [];
      try {
        const key = Deno.env.get("GEMINI_API_KEY");
        if (!key) throw new Error("not_configured");
        let pageToken = "";
        for (let page = 0; page < 20; page++) {
          const list = await fetch(
            `https://generativelanguage.googleapis.com/v1beta/models${pageToken ? `?pageToken=${encodeURIComponent(pageToken)}` : ""}`,
            {
              headers: { "x-goog-api-key": key },
              signal: AbortSignal.timeout(15000),
            },
          );
          if (!list.ok) throw new Error(`model_list_http_${list.status}`);
          const data = await list.json();
          for (const entry of data.models ?? [])
            if (entry.supportedGenerationMethods?.includes("generateContent"))
              availableModels.push(String(entry.name).replace(/^models\//, ""));
          pageToken = data.nextPageToken ?? "";
          if (!pageToken) break;
        }
        if (!availableModels.includes(model))
          throw new Error("model_unavailable");
        // A generated, non-personal label verifies image input, units and JSON.
        const bytes = Uint8Array.from(atob(probeLabelPng), (c) =>
          c.charCodeAt(0),
        );
        const { result } = await analyzeImage(
          key,
          model,
          bytes,
          "image/png",
          "label",
          "Synthetic label connectivity check. Read the printed values per 100 g.",
        );
        const food = result.items[0];
        if (
          !food ||
          food.basis !== "g" ||
          food.per100.kcal !== 250 ||
          food.per100.protein !== 10 ||
          food.per100.carbs !== 40 ||
          food.per100.fat !== 6
        )
          throw new Error("invalid_output");
        ok = true;
      } catch (e) {
        // Only bounded error categories and HTTP status; never provider bodies.
        const status = (e as { status?: number }).status;
        probeError = e instanceof Error ? e.message : "probe_failed";
        if (status) probeError += `_http_${status}`;
      }
      await admin.rpc("health_probe_result", { p_model: model, p_ok: ok });
      return json({ model, ok, error: probeError, availableModels });
    }
    const used = await referencedImages(admin);
    let removed = 0;
    const folders: string[] = [];
    for (let offset = 0; ; offset += 100) {
      const { data, error } = await admin.storage
        .from("health-images")
        .list("", { limit: 100, offset });
      if (error) throw new Error("failed");
      for (const folder of data ?? []) folders.push(folder.name);
      if (!data || data.length < 100) break;
    }
    // List before removing: deleting virtual folders must not shift pagination.
    for (const folder of folders) {
      const stale: string[] = [];
      for (let offset = 0; ; offset += 100) {
        const { data: files, error } = await admin.storage
          .from("health-images")
          .list(folder, { limit: 100, offset });
        if (error) throw new Error("failed");
        for (const file of files ?? []) {
          const path = `${folder}/${file.name}`;
          if (
            !used.has(path) &&
            Date.parse(file.created_at ?? "") < Date.now() - 86400000
          )
            stale.push(path);
        }
        if (!files || files.length < 100) break;
      }
      for (let i = 0; i < stale.length; i += 100) {
        const chunk = stale.slice(i, i + 100);
        const { error } = await admin.storage
          .from("health-images")
          .remove(chunk);
        if (error) throw new Error("failed");
        removed += chunk.length;
      }
    }
    await admin
      .from("nutrition_analyses")
      .delete()
      .lt("created_at", new Date(Date.now() - 30 * 86400000).toISOString());
    return json({ ok: true, removed });
  } catch (e) {
    return failure(e);
  }
});

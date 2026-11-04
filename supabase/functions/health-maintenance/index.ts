import {
  adminClient,
  body,
  cors,
  failure,
  json,
  referencedImages,
} from "../_shared/health-http.ts";
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
    const { error } = await admin.rpc("health_service_settings");
    if (error) throw new Error("failed");
    if (input.probe) {
      // Legacy label-to-AI probing is retired. Label values now use product
      // lookup or explicitly confirmed printed data; never run inference here.
      return json({ ok: false, error: "label_lookup_required" }, 400);
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
    const expiry = new Date(Date.now() - 30 * 86400000).toISOString();
    const { error: cleanupError } = await admin
      .from("wellness_ai_jobs")
      .delete()
      .lt("created_at", expiry);
    if (cleanupError) throw new Error("failed");
    // Operational counters contain no meal/plan content.
    const { error: usageError } = await admin.rpc("wellness_prune_usage");
    if (usageError) throw new Error("failed");
    return json({ ok: true, removed });
  } catch (e) {
    return failure(e);
  }
});

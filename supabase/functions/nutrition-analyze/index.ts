// Compatibility endpoint: all meal estimates use the same free-only Wellness
// pipeline. Label mode is rejected there before any model call or reservation.
import { body, cors, failure, json } from "../_shared/health-http.ts";
import { handleWellness } from "../_shared/wellness-handler.ts";
import { record } from "../_shared/wellness-core.ts";
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const input = record(await body(req));
    return await handleWellness(
      new Request(req, { body: JSON.stringify({ ...input, action: "nutrition" }) }),
      (key) => Deno.env.get(key),
    );
  } catch (e) {
    return failure(e);
  }
});

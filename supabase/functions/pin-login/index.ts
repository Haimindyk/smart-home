import { createClient } from "npm:@supabase/supabase-js@2.110.1";
import { adminClient, json, cors, body } from "../_shared/health-http.ts";
async function derivePassword(pepper: string, memberId: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(pepper),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return Array.from(
    new Uint8Array(
      await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(memberId)),
    ),
  )
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const input = await body(req);
    if (typeof input.pin !== "string" || !/^\d{4}$/.test(input.pin))
      return json({ error: "invalid_pin" });
    const admin = adminClient();
    const { data: rows, error } = await admin.rpc("verify_health_pin", {
      p_pin: input.pin,
    });
    let member = rows?.[0];
    if (error) {
      if (error.message.includes("rate_limited"))
        return json({ error: "rate_limited" });
      // During a rolling release the server endpoint is deployed before the
      // hash migration. Only a closed release gate permits this server-only
      // compatibility lookup. Never reintroduce local/browser PIN matching.
      const { data: release } = await admin
        .from("health_release_state")
        .select("personal_access_ready")
        .eq("id", true)
        .single();
      if (
        error.code !== "PGRST202" ||
        !release ||
        release.personal_access_ready
      )
        return json({ error: "not_configured" });
      const { data: legacy, error: legacyError } = await admin
        .from("members")
        .select("id,email,user_id")
        .eq("pin", input.pin)
        .maybeSingle();
      if (legacyError) return json({ error: "not_configured" });
      member = legacy;
    }
    if (!member) return json({ error: "invalid_pin" });
    const { data: pepper, error: pepperError } = await admin.rpc(
      "get_pin_login_pepper",
    );
    if (pepperError || !pepper) return json({ error: "not_configured" });
    const password = await derivePassword(pepper, member.id);
    let userId = member.user_id;
    if (userId) {
      const { error } = await admin.auth.admin.updateUserById(userId, {
        password,
      });
      if (error) return json({ error: "sign_in_failed" });
    } else {
      const { data, error } = await admin.auth.admin.createUser({
        email: member.email,
        password,
        email_confirm: true,
        app_metadata: { health_pin_account: true },
      });
      if (error || !data.user) return json({ error: "provisioning_failed" });
      userId = data.user.id;
      const { error: linkError } = await admin
        .from("members")
        .update({ user_id: userId })
        .eq("id", member.id)
        .is("user_id", null);
      if (linkError) return json({ error: "provisioning_failed" });
    }
    const anon = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { auth: { persistSession: false } },
    );
    const { data, error: signError } = await anon.auth.signInWithPassword({
      email: member.email,
      password,
    });
    if (signError || !data.session) return json({ error: "sign_in_failed" });
    return json({
      memberId: member.id,
      access_token: data.session.access_token,
      refresh_token: data.session.refresh_token,
    });
  } catch {
    return json({ error: "unexpected" });
  }
});

// Turns a member's 4-digit PIN into a real, signed-in Supabase Auth session
// for that member — the missing piece that lets RLS actually tell members
// apart (see migration 0033/0034's board privacy). Every PIN check in this
// app used to happen entirely client-side (see identity-gate.tsx before this
// function existed): the whole `members` table, PINs included, was already
// downloaded to render the pad, and "login" was just a local array match —
// fine for picking who's using a shared device, but no security boundary at
// all. This function is the one place that check now happens for real, with
// the full members table never touched from the client for this purpose.
//
// Every response — success or failure — is HTTP 200 with a JSON body,
// `{ error: "..." }` on failure. supabase-js's functions.invoke() doesn't
// reliably hand back a parsed body for a non-2xx response across versions,
// and the caller (identity-gate.tsx) needs to tell "definitely wrong PIN"
// apart from "this function isn't deployed/configured yet" so it can fall
// back to the household's existing local-match login instead of ever
// looking broken during rollout. The one genuine exception is malformed
// input (missing/non-JSON body) — a client bug, not a login outcome — which
// stays 400.
//
// Deployed with verify_jwt disabled — this *is* the login step, called by a
// device with no session yet, same reasoning as supabase/functions/assistant.
//
// This is a Deno module (Supabase Edge Runtime), not part of the Next.js
// app's TypeScript project — see tsconfig.json / eslint.config.mjs, both of
// which exclude supabase/functions/**.

import { createClient } from "npm:@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...CORS_HEADERS } });
}

/** Deterministic per-member password for the synthetic Supabase Auth account
 * behind their PIN — never exposed to any client, never stored (recomputed
 * identically on every login), and unrelated to the PIN's actual digits so
 * this account's password strength doesn't depend on a 4-digit PIN. */
async function derivePassword(pepper: string, memberId: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(pepper), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(memberId));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let body: { pin?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const pin = typeof body.pin === "string" ? body.pin.trim() : "";
  if (!pin) return json({ error: "missing_pin" }, 400);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    // The one place a PIN check carries real authority — every other copy
    // of this comparison (the identity-gate pad) is client-side UX only.
    const { data: member, error: lookupError } = await admin
      .from("members")
      .select("id, email, user_id")
      .eq("pin", pin)
      .maybeSingle();
    if (lookupError || !member) return json({ error: "invalid_pin" });

    const { data: pepper, error: pepperError } = await admin.rpc("get_pin_login_pepper");
    if (pepperError || !pepper) return json({ error: "not_configured" });

    const password = await derivePassword(pepper as string, member.id);

    // Idempotent: create the member's synthetic auth account on first login
    // (public.link_member_on_signup, see migration 0033, then stamps
    // members.user_id automatically), or just re-sync its password on every
    // later login so this stays self-healing if anything ever drifts.
    if (member.user_id) {
      await admin.auth.admin.updateUserById(member.user_id, { password });
    } else {
      const { error: createError } = await admin.auth.admin.createUser({ email: member.email, password, email_confirm: true });
      if (createError) return json({ error: "provisioning_failed" });
    }

    const anon = createClient(supabaseUrl, anonKey);
    const { data: signIn, error: signInError } = await anon.auth.signInWithPassword({ email: member.email, password });
    if (signInError || !signIn.session) return json({ error: "sign_in_failed" });

    return json({
      memberId: member.id,
      access_token: signIn.session.access_token,
      refresh_token: signIn.session.refresh_token,
    });
  } catch (err) {
    console.error("pin-login: unexpected failure", err);
    return json({ error: "unexpected" });
  }
});

// Supabase Edge Function: sends a push notification to one or more devices
// via APNs (HTTP/2, token-based auth). Called from Postgres triggers/cron
// (see 0005_push_notifications.sql's notify_devices()), not directly by the
// app.
//
// Required secrets (set with `supabase secrets set ...` — see
// ios/README.md for the full walkthrough):
//   APNS_KEY_ID       - the Key ID of your APNs Auth Key (.p8)
//   APNS_TEAM_ID      - your Apple Developer Team ID
//   APNS_PRIVATE_KEY  - the contents of the .p8 file, PEM as-is (with
//                        the BEGIN/END PRIVATE KEY lines)
//   APNS_BUNDLE_ID    - the app's bundle id (com.haimindyk.yachad)
//   APNS_ENVIRONMENT  - "sandbox" (dev builds / Xcode) or "production"
//                        (TestFlight/App Store)
//   PUSH_EDGE_SECRET  - a random string you also store in Supabase Vault
//                        as `push_edge_secret` — the shared secret this
//                        function checks the caller's Authorization
//                        header against, so only your own database can
//                        invoke it.
//
// Deploy with: supabase functions deploy send-push --no-verify-jwt
// (--no-verify-jwt because the caller here is Postgres via pg_net with our
// own bearer secret, not a logged-in Supabase user — there is no such
// thing in this app).

import { createClient } from "jsr:@supabase/supabase-js@2";

interface NotifyRequest {
  deviceIds: string[];
  title: string;
  body: string;
  data?: Record<string, unknown>;
}

const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";
const APNS_PRIVATE_KEY_PEM = Deno.env.get("APNS_PRIVATE_KEY") ?? "";
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "";
const APNS_ENVIRONMENT = Deno.env.get("APNS_ENVIRONMENT") ?? "sandbox";
const PUSH_EDGE_SECRET = Deno.env.get("PUSH_EDGE_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const APNS_HOST = APNS_ENVIRONMENT === "production"
  ? "https://api.push.apple.com"
  : "https://api.sandbox.push.apple.com";

let cachedToken: { jwt: string; issuedAt: number } | null = null;

function base64url(bytes: ArrayBuffer | Uint8Array): string {
  const buf = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let str = "";
  for (const byte of buf) str += String.fromCharCode(byte);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importApnsKey(pem: string): Promise<CryptoKey> {
  const stripped = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = Uint8Array.from(atob(stripped), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    raw,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

// APNs auth tokens are valid up to an hour; Apple asks callers not to
// mint a new one more than once per ~20 minutes.
async function getApnsJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && now - cachedToken.issuedAt < 60 * 15) {
    return cachedToken.jwt;
  }

  const header = { alg: "ES256", kid: APNS_KEY_ID };
  const claims = { iss: APNS_TEAM_ID, iat: now };
  const unsigned = `${base64url(new TextEncoder().encode(JSON.stringify(header)))}.${base64url(new TextEncoder().encode(JSON.stringify(claims)))}`;

  const key = await importApnsKey(APNS_PRIVATE_KEY_PEM);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(unsigned),
  );

  const jwt = `${unsigned}.${base64url(signature)}`;
  cachedToken = { jwt, issuedAt: now };
  return jwt;
}

async function sendToToken(apnsToken: string, title: string, body: string, data: Record<string, unknown>): Promise<void> {
  const jwt = await getApnsJwt();
  const payload = {
    aps: { alert: { title, body }, sound: "default" },
    ...data,
  };

  // Deno's fetch negotiates HTTP/2 automatically against Apple's servers.
  const response = await fetch(`${APNS_HOST}/3/device/${apnsToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": APNS_BUNDLE_ID,
      "apns-push-type": "alert",
      "apns-priority": "10",
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const reason = await response.text();
    console.error(`APNs rejected token ${apnsToken.slice(0, 8)}…: ${response.status} ${reason}`);
    // A 410 means the token is no longer valid — drop it so we stop
    // trying. Anything else (rate limit, bad payload) is left as-is;
    // it'll self-correct or show up in function logs.
    if (response.status === 410) {
      const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
      await supabase.from("push_tokens").delete().eq("apns_token", apnsToken);
    }
  }
}

Deno.serve(async (req) => {
  if (req.headers.get("authorization") !== `Bearer ${PUSH_EDGE_SECRET}`) {
    return new Response("unauthorized", { status: 401 });
  }
  if (!APNS_KEY_ID || !APNS_TEAM_ID || !APNS_PRIVATE_KEY_PEM || !APNS_BUNDLE_ID) {
    return new Response("APNs is not configured on this function", { status: 501 });
  }

  const { deviceIds, title, body, data }: NotifyRequest = await req.json();
  if (!deviceIds?.length) {
    return new Response("ok (no devices)", { status: 200 });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: tokens, error } = await supabase
    .from("push_tokens")
    .select("apns_token")
    .in("device_id", deviceIds);

  if (error) {
    return new Response(`lookup failed: ${error.message}`, { status: 500 });
  }

  await Promise.all((tokens ?? []).map((t) => sendToToken(t.apns_token, title, body, data ?? {})));

  return new Response("ok", { status: 200 });
});

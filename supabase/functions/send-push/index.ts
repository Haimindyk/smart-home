// Fired by the `activity_log_notify_push` trigger (see
// supabase/migrations/0006_push_notifications.sql) once per activity_log
// insert. Fans a single activity_log row out to every subscribed device via
// Web Push, respecting each member's notification_prefs.
//
// Only *human* activity is pushed: someone adding, completing or deleting an
// item, or deliberately sending a broadcast. Scheduled reminders and the
// assistant's own unsolicited messages were removed in migration 0031 — the
// trigger already filters those out, and the guards below repeat the check so
// a stale database can't get anything through.
//
// This function has zero manually-configured secrets: SUPABASE_URL and
// SUPABASE_ANON_KEY are auto-injected by the Edge Runtime, and the VAPID
// keypair is fetched at request time via get_push_config(), re-presenting
// the same `Authorization: Bearer <secret>` value the trigger invoked us
// with. That RPC call doubles as this function's entire auth check: a
// bad/missing secret makes it raise, and we never learn the keys.
//
// This is a Deno module (Supabase Edge Runtime), not part of the Next.js
// app's TypeScript project — see tsconfig.json / eslint.config.mjs, both of
// which exclude supabase/functions/**.

import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3";

type ActivityLogRow = {
  id: string;
  entity_type: string;
  entity_id: string;
  action: string;
  actor_id: string | null;
  summary: string | null;
  created_at: string;
  seq?: number;
};

type PushSubscriptionRow = {
  id: string;
  member_id: string | null;
  endpoint: string;
  p256dh: string;
  auth: string;
};

type NotificationPrefsRow = {
  member_id: string;
  on_create: boolean;
  on_complete: boolean;
  on_assigned_me: boolean;
  on_shopping: boolean;
  on_delete: boolean;
  on_broadcast: boolean;
  muted: boolean;
};

type MemberRow = {
  id: string;
  email: string | null;
  display_name: string;
  avatar_emoji: string | null;
  avatar_photo_url: string | null;
  locale: string | null;
};

const DEFAULT_PREFS: Omit<NotificationPrefsRow, "member_id"> = {
  on_create: true,
  on_complete: true,
  on_assigned_me: true,
  on_shopping: true,
  on_delete: true,
  on_broadcast: true,
  muted: false,
};

// Tiny, self-contained i18n for notification bodies. This function is
// deployed standalone (no shared bundle with the Next app), so we don't
// import src/lib/i18n/messages.ts — just enough translation to make the
// body read naturally, keyed by the *recipient's* members.locale.
const VERBS: Record<string, { he: string; en: string }> = {
  created: { he: "נוצר/ה", en: "created" },
  updated: { he: "עודכן/ה", en: "updated" },
  renamed: { he: "שונה שם", en: "renamed" },
  completed: { he: "הושלם/ה", en: "completed" },
  uncompleted: { he: "בוטל סימון בוצע", en: "marked not done" },
  deleted: { he: "נמחק/ה", en: "deleted" },
  restored: { he: "שוחזר/ה", en: "restored" },
};

function verbFor(action: string, locale: string | null): string {
  const entry = VERBS[action];
  if (!entry) return action;
  return locale === "he" ? entry.he : entry.en;
}

// Web push bodies get visually truncated by the OS/browser notification UI
// somewhere around 3-4 lines with no ellipsis of its own — a mid-word cutoff
// reads as broken. This is a defensive cap applied uniformly to every
// notification body (a per-item change or a human broadcast), truncating at the
// last word boundary and adding our own "…" so a long body still reads as a
// complete-looking sentence instead of getting chopped by the platform.
const MAX_PUSH_BODY_LENGTH = 200;

function truncateForPush(text: string, maxLen = MAX_PUSH_BODY_LENGTH): string {
  if (text.length <= maxLen) return text;
  const slice = text.slice(0, maxLen);
  const lastSpace = slice.lastIndexOf(" ");
  const cut = lastSpace > maxLen * 0.6 ? slice.slice(0, lastSpace) : slice;
  return `${cut.trimEnd()}…`;
}


// ---------------------------------------------------------------------------
// Native iOS delivery through APNs (token-based auth). The only secret is APNS_KEY_P8 (the .p8 contents);
// the key id, team id and bundle id are identifiers, not secrets, and can be overridden with APNS_KEY_ID,
// APNS_TEAM_ID and APNS_TOPIC. Without APNS_KEY_P8 the iOS path is skipped and Web Push keeps working as before.
// ---------------------------------------------------------------------------
type ApnsDeviceRow = { id: string; member_id: string | null; token: string; environment: string };

let cachedApnsJwt: { token: string; issuedAt: number } | null = null;

function base64Url(bytes: Uint8Array | string): string {
  const raw = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let binary = "";
  for (const b of raw) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function apnsJwt(): Promise<string | null> {
  const pem = Deno.env.get("APNS_KEY_P8");
  const keyId = Deno.env.get("APNS_KEY_ID") ?? "TN6SK4LJ85";
  const teamId = Deno.env.get("APNS_TEAM_ID") ?? "D9LMURYTY5";
  if (!pem || !keyId || !teamId) return null;
  const now = Math.floor(Date.now() / 1000);
  // APNs rejects tokens older than an hour and throttles re-issuing; reuse one for ~50 minutes.
  if (cachedApnsJwt && now - cachedApnsJwt.issuedAt < 3000) return cachedApnsJwt.token;
  const der = Uint8Array.from(atob(pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "")), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const unsigned = `${base64Url(JSON.stringify({ alg: "ES256", kid: keyId }))}.${base64Url(JSON.stringify({ iss: teamId, iat: now }))}`;
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsigned)));
  const token = `${unsigned}.${base64Url(signature)}`;
  cachedApnsJwt = { token, issuedAt: now };
  return token;
}

/** Returns "ok", "dead" (the token should be removed) or "failed". */
async function sendApns(device: ApnsDeviceRow, payload: { title: string; body: string; tag: string }): Promise<"ok" | "dead" | "failed"> {
  const jwt = await apnsJwt();
  const topic = Deno.env.get("APNS_TOPIC") ?? "com.haimindyk.smarthome.wellness";
  if (!jwt) return "failed";
  const host = device.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const response = await fetch(`https://${host}/3/device/${device.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify({ aps: { alert: { title: payload.title, body: payload.body }, sound: "default", "thread-id": payload.tag } }),
  });
  if (response.ok) return "ok";
  const reason = (await response.json().catch(() => ({})) as { reason?: string }).reason;
  console.error(`send-push: APNs ${response.status} ${reason ?? ""} for device ${device.id}`);
  if (response.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered" || reason === "DeviceTokenNotForTopic") return "dead";
  return "failed";
}

function getBearerToken(req: Request): string | null {
  const header = req.headers.get("Authorization") ?? req.headers.get("authorization");
  if (!header?.startsWith("Bearer ")) return null;
  const token = header.slice("Bearer ".length).trim();
  return token.length > 0 ? token : null;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  const secret = getBearerToken(req);
  if (!secret) return json({ error: "missing bearer token" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseAnonKey);

  // Auth check: get_push_config raises if the secret doesn't match the one
  // in Vault, which supabase-js surfaces as `error` rather than a throw.
  const { data: config, error: configError } = await supabase
    .rpc("get_push_config", { p_secret: secret })
    .single();

  if (configError || !config?.vapid_public_key || !config?.vapid_private_key) {
    return json({ error: "unauthorized" }, 401);
  }

  webpush.setVapidDetails("mailto:noreply@kh.family", config.vapid_public_key, config.vapid_private_key);

  let activity: ActivityLogRow;
  try {
    activity = await req.json();
  } catch {
    return json({ error: "invalid body" }, 400);
  }

  const { entity_type: entityType, entity_id: entityId, action, actor_id: actorId, summary } = activity;

  // Notification kinds that no longer exist (migration 0031): scheduled
  // due-date/event reminders and the assistant's one-on-one notes. The
  // trigger stopped emitting them, so anything still arriving here is a
  // stale database — drop it rather than push it.
  if (action === "due" || action === "personal") {
    return json({ sent: 0, skipped: 0, reason: "non_human_notification" });
  }

  // Assignee targeting only applies to tasks/chores — sections have no
  // assignees. A new/renamed section still gets a (generic, non-targeted)
  // notification below; we just skip this lookup for it.
  let assigneeIds: string[] = [];
  let isShopping = false;

  if (entityType === "task" || entityType === "chore") {
    const table = entityType === "task" ? "tasks" : "chores";
    const { data: entityRow } = await supabase
      .from(table)
      .select("assignee_member_ids, section_id")
      .eq("id", entityId)
      .maybeSingle();

    // The row may have been deleted since the activity was logged (e.g. a
    // rapid create-then-delete) — treat that as "no assignees" rather than
    // failing the whole notification.
    if (entityRow) {
      assigneeIds = (entityRow.assignee_member_ids as string[] | null) ?? [];
      if (entityType === "task" && entityRow.section_id) {
        const { data: section } = await supabase
          .from("sections")
          .select("kind")
          .eq("id", entityRow.section_id as string)
          .maybeSingle();
        isShopping = section?.kind === "shopping";
      }
    }
  }

  const [{ data: subscriptions }, { data: prefsRows }, { data: members }, { data: apnsDevices }] = await Promise.all([
    supabase.from("push_subscriptions").select("id, member_id, endpoint, p256dh, auth"),
    supabase.from("notification_prefs").select("*"),
    supabase.from("members").select("id, email, display_name, avatar_emoji, avatar_photo_url, locale"),
    supabase.from("apns_devices").select("id, member_id, token, environment"),
  ]);

  const prefsByMember = new Map<string, NotificationPrefsRow>();
  for (const row of (prefsRows ?? []) as NotificationPrefsRow[]) {
    prefsByMember.set(row.member_id, row);
  }

  const membersById = new Map<string, MemberRow>();
  for (const member of (members ?? []) as MemberRow[]) {
    membersById.set(member.id, member);
  }

  const actor = actorId ? membersById.get(actorId) : undefined;
  const actorName = actor ? [actor.avatar_emoji, actor.display_name].filter(Boolean).join(" ") : null;

  // Only people trigger notifications (migration 0031). The assistant still
  // writes to activity_log when a human applies one of her proposals — but
  // those are attributed to the person who tapped Apply, not to her, so
  // anything actually authored by her row is something she decided to send.
  if (actor?.email === "assistant@kh.family") {
    return json({ sent: 0, skipped: (subscriptions ?? []).length, reason: "non_human_notification" });
  }

  let sent = 0;
  let skipped = 0;

  // Per-member decision shared by Web Push and APNs: null = stay silent, otherwise the notification content.
  const buildNotification = (memberId: string): { title: string; body: string; tag: string; icon?: string } | null => {
    const prefs = prefsByMember.get(memberId) ?? { member_id: memberId, ...DEFAULT_PREFS };
    if (prefs.muted) {
      return null;
    }

    const isAssignee = assigneeIds.includes(memberId);

    // Targeting precedence (deliberate, see PR description):
    // 1. Being assigned is the strongest signal. If the member has
    //    on_assigned_me on, they hear about it even if on_create happens
    //    to be off for them — an assignment is arguably a distinct kind
    //    of event from "someone created something", even though both
    //    ride on the same activity_log INSERT.
    // 2. Shopping-list items are gated purely by on_shopping, standing in
    //    for on_create/on_complete for that category (so someone can mute
    //    "created"/"completed" noise in general but keep shopping pings,
    //    or vice versa).
    // 3. Everything else falls back to the action-specific pref. Actions
    //    with no pref of their own (renamed/moved/updated/uncompleted)
    //    stay silent — they're edits to something you already heard
    //    about, not a new thing to look at.
    let notify: boolean;
    if (action === "message") {
      // A deliberate broadcast from a member — gated purely by on_broadcast,
      // never by mute-by-assignee/shopping/etc. logic below.
      notify = prefs.on_broadcast;
    } else if (isAssignee && prefs.on_assigned_me) {
      notify = true;
    } else if (isShopping) {
      notify = prefs.on_shopping;
    } else if (action === "created") {
      notify = prefs.on_create;
    } else if (action === "completed") {
      notify = prefs.on_complete;
    } else if (action === "deleted" || action === "restored") {
      notify = prefs.on_delete;
    } else {
      notify = false;
    }

    if (!notify) {
      return null;
    }

    const recipient = membersById.get(memberId);
    let title: string;
    let body: string;
    if (action === "message") {
      title = actorName ? `📣 ${actorName}` : "📣 K&H";
      body = summary ?? "";
    } else {
      const verb = verbFor(action, recipient?.locale ?? null);
      title = actorName ?? "K&H";
      body = summary ? `${verb} ${summary}` : verb;
    }

    return { title, body: truncateForPush(body), tag: `${entityType}-${entityId}`, icon: actor?.avatar_photo_url ?? undefined };
  };

  await Promise.all(
    ((subscriptions ?? []) as PushSubscriptionRow[]).map(async (sub) => {
      // Never notify the person who made the change themselves.
      if (!sub.member_id || sub.member_id === actorId) {
        skipped++;
        return;
      }
      const note = buildNotification(sub.member_id);
      if (!note) {
        skipped++;
        return;
      }
      const payload = { title: note.title, body: note.body, url: "/", tag: note.tag, icon: note.icon };
      try {
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
          JSON.stringify(payload)
        );
        sent++;
      } catch (err) {
        const statusCode = (err as { statusCode?: number; status?: number })?.statusCode ??
          (err as { statusCode?: number; status?: number })?.status;
        if (statusCode === 410 || statusCode === 404) {
          // Dead subscription (unsubscribed, browser data cleared, etc.) — stop retrying it forever.
          await supabase.from("push_subscriptions").delete().eq("id", sub.id);
        }
        console.error(`send-push: failed for subscription ${sub.id}`, statusCode, err);
        skipped++;
      }
    })
  );

  // Native iOS devices (APNs), same rules and preferences.
  await Promise.all(
    ((apnsDevices ?? []) as ApnsDeviceRow[]).map(async (device) => {
      if (!device.member_id || device.member_id === actorId) {
        skipped++;
        return;
      }
      const note = buildNotification(device.member_id);
      if (!note) {
        skipped++;
        return;
      }
      try {
        const result = await sendApns(device, note);
        if (result === "ok") sent++;
        else {
          if (result === "dead") await supabase.from("apns_devices").delete().eq("id", device.id);
          skipped++;
        }
      } catch (err) {
        console.error(`send-push: APNs failed for device ${device.id}`, err);
        skipped++;
      }
    })
  );

  return json({ sent, skipped });
});

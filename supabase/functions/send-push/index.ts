// Fired by the `activity_log_notify_push` trigger (see
// supabase/migrations/0006_push_notifications.sql) once per activity_log
// insert. Fans a single activity_log row out to every subscribed device via
// Web Push, respecting each member's notification_prefs.
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
  muted: boolean;
};

type MemberRow = {
  id: string;
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

  const [{ data: subscriptions }, { data: prefsRows }, { data: members }] = await Promise.all([
    supabase.from("push_subscriptions").select("id, member_id, endpoint, p256dh, auth"),
    supabase.from("notification_prefs").select("*"),
    supabase.from("members").select("id, display_name, avatar_emoji, avatar_photo_url, locale"),
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

  let sent = 0;
  let skipped = 0;

  await Promise.all(
    ((subscriptions ?? []) as PushSubscriptionRow[]).map(async (sub) => {
      // Never notify the person who made the change themselves.
      if (!sub.member_id || sub.member_id === actorId) {
        skipped++;
        return;
      }

      const prefs = prefsByMember.get(sub.member_id) ?? { member_id: sub.member_id, ...DEFAULT_PREFS };
      if (prefs.muted) {
        skipped++;
        return;
      }

      const isAssignee = assigneeIds.includes(sub.member_id);

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
      // 3. Everything else falls back to the action-specific pref.
      let notify: boolean;
      if (isAssignee && prefs.on_assigned_me) {
        notify = true;
      } else if (isShopping) {
        notify = prefs.on_shopping;
      } else if (action === "created") {
        notify = prefs.on_create;
      } else if (action === "completed") {
        notify = prefs.on_complete;
      } else {
        notify = false;
      }

      if (!notify) {
        skipped++;
        return;
      }

      const recipient = membersById.get(sub.member_id);
      const verb = verbFor(action, recipient?.locale ?? null);
      const title = actorName ?? "K&H";
      const body = summary ? `${verb} ${summary}` : verb;

      const payload = {
        title,
        body,
        url: "/",
        tag: `${entityType}-${entityId}`,
        icon: actor?.avatar_photo_url ?? undefined,
      };

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
          // Dead subscription (unsubscribed, browser data cleared, etc.) —
          // stop retrying it forever.
          await supabase.from("push_subscriptions").delete().eq("id", sub.id);
        }
        console.error(`send-push: failed for subscription ${sub.id}`, statusCode, err);
        skipped++;
      }
    })
  );

  return json({ sent, skipped });
});

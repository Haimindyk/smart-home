"use client";

import { X } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useIdentity } from "@/lib/identity";
import { useT } from "@/lib/i18n/store";

/** Mika's private, one-on-one notes (see supabase/functions/assistant's
 * "personal_checkin" mode + migration 0026's ai_private_messages table) —
 * shown only to the member they're addressed to. Like the rest of this
 * app's identity model, that's a display-layer filter (actingMemberId is
 * self-declared, not verified), not real access control — see identity.ts. */
export function PersonalNoteCards() {
  const actingMemberId = useIdentity((s) => s.actingMemberId);
  const aiPrivateMessages = useAppStore((s) => s.aiPrivateMessages);
  const markPrivateMessageRead = useAppStore((s) => s.markPrivateMessageRead);
  const t = useT();

  if (!actingMemberId) return null;

  const unread = Object.values(aiPrivateMessages)
    .filter((m) => m.member_id === actingMemberId && !m.read_at)
    .sort((a, b) => (a.created_at < b.created_at ? 1 : -1));

  if (unread.length === 0) return null;

  return (
    <div className="mb-4 flex flex-col gap-2">
      {unread.map((m) => (
        <div key={m.id} className="glass surface-shadow flex items-center gap-3 rounded-2xl p-3.5 ring-1 ring-fuchsia-500/30">
          <span className="text-xl">💜</span>
          <p dir="auto" className="flex-1 text-sm">
            {m.summary}
          </p>
          <button
            type="button"
            className="rounded-full p-1.5 text-muted-foreground hover:bg-muted"
            onClick={() => void markPrivateMessageRead(m.id)}
            aria-label={t("dismiss")}
          >
            <X className="size-4" />
          </button>
        </div>
      ))}
    </div>
  );
}

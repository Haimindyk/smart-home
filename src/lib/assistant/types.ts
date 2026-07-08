import type { ChoreFreq } from "@/types/domain";
import type { SectionKind } from "@/types/domain";
import type { EventKind } from "@/types/domain";

/**
 * The assistant's action vocabulary — what the Edge Function (supabase/
 * functions/assistant) can *propose*, never apply directly. Each variant
 * maps to exactly one useAppStore mutation in apply-actions.ts, so a
 * confirmed action gets the same optimistic UI, offline queueing, and
 * activity-log attribution as a human action would.
 *
 * Kept in sync by hand with the TOOLS array in the Edge Function — that's a
 * separate Deno deploy, not part of this Next.js build (see
 * supabase/functions/assistant/index.ts).
 */
export type ProposedAction =
  | { type: "create_task"; sectionId: string; title: string; quantity?: number | null; unit?: string | null; notes?: string | null }
  | { type: "create_section"; name: string; kind: SectionKind; emoji?: string | null }
  | { type: "toggle_task_completed"; taskId: string }
  | { type: "create_chore"; sectionId: string; title: string; freq: ChoreFreq }
  | { type: "complete_chore"; choreId: string }
  | { type: "create_family_event"; title: string; kind: EventKind; eventDate: string; endDate?: string | null }
  | { type: "send_broadcast"; message: string };

export type AssistantResponse = {
  reply: string;
  proposedActions: ProposedAction[];
};

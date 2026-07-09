import { useAppStore } from "@/lib/store/app-store";
import { rankAtEnd } from "@/lib/ordering/rank";
import type { ProposedAction } from "./types";

/** Seeded in migration 0022 — a dedicated member row so History reads
 * honestly ("🤖 העוזר added milk") instead of crediting whichever human
 * happened to tap "confirm". */
const ASSISTANT_EMAIL = "assistant@kh.family";

function assistantMemberId(): string | null {
  const members = useAppStore.getState().members;
  return Object.values(members).find((m) => m.email === ASSISTANT_EMAIL)?.id ?? null;
}

/**
 * Applies one confirmed proposed action through the same useAppStore
 * mutations a human action would use — this is the only place either the
 * chat assistant or a proactive insight card's action actually writes
 * anything, so optimistic UI, the offline queue, and realtime sync all
 * behave identically to a human doing it themselves.
 *
 * Returns the new row's id for create_task/create_section, so a caller
 * applying several actions in sequence (see assistant-dialog.tsx) can
 * resolve a move_task's "NEW_SECTION" sentinel to the section that was
 * just created earlier in the same batch.
 */
export async function applyProposedAction(action: ProposedAction): Promise<string | undefined> {
  const store = useAppStore.getState();
  const actorId = assistantMemberId();

  switch (action.type) {
    case "create_task":
      return await store.createTask({
        sectionId: action.sectionId,
        title: action.title,
        createdBy: actorId,
        extra: {
          quantity: action.quantity ?? null,
          unit: action.unit ?? null,
          notes: action.notes ?? null,
        },
      });
    case "create_section":
      return await store.createSection({
        name: action.name,
        kind: action.kind,
        emoji: action.emoji ?? undefined,
        createdBy: actorId,
      });
    case "toggle_task_completed":
      await store.toggleTaskCompleted(action.taskId, actorId);
      return;
    case "move_task": {
      const siblings = Object.values(store.tasks).filter(
        (t) => t.section_id === action.sectionId && t.parent_task_id === null && !t.deleted_at
      );
      const lastPosition = siblings.sort((a, b) => (a.position > b.position ? -1 : 1))[0]?.position;
      await store.updateTask(action.taskId, {
        section_id: action.sectionId,
        parent_task_id: null,
        position: rankAtEnd(lastPosition),
      });
      return;
    }
    case "create_chore":
      // createChore attributes to the currently-acting human device identity
      // rather than an explicit createdBy param (an existing asymmetry with
      // createTask/createSection/createFamilyEvent) — not something this
      // feature reworks.
      await store.createChore({ sectionId: action.sectionId, title: action.title, freq: action.freq });
      return;
    case "complete_chore":
      if (!actorId) return;
      await store.completeChore(action.choreId, actorId);
      return;
    case "create_family_event":
      await store.createFamilyEvent({
        title: action.title,
        kind: action.kind,
        eventDate: action.eventDate,
        endDate: action.endDate ?? null,
        recurrence: "none",
        createdBy: actorId,
      });
      return;
    case "send_broadcast":
      await store.sendBroadcastMessage(action.message, actorId);
      return;
  }
}

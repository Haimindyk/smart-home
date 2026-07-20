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

export type ApplyResult = {
  /** The new row's id, for create_task/create_section/create_chore/create_family_event —
   * lets a caller applying several actions in sequence (see assistant-dialog.tsx)
   * resolve a move_task's "NEW_SECTION" sentinel to the section just created
   * earlier in the same batch. */
  createdId?: string;
  /** Reverses this action, if it's safely reversible. Missing for
   * complete_chore (no clean way to un-record a completion without new
   * plumbing). */
  undo?: () => Promise<void>;
};

/**
 * Applies one confirmed proposed action through the same useAppStore
 * mutations a human action would use — this is the only place either the
 * chat assistant or a proactive insight card's action actually writes
 * anything, so optimistic UI, the offline queue, and realtime sync all
 * behave identically to a human doing it themselves.
 */
export async function applyProposedAction(action: ProposedAction): Promise<ApplyResult> {
  const store = useAppStore.getState();
  const actorId = assistantMemberId();

  switch (action.type) {
    case "create_task": {
      const id = await store.createTask({
        sectionId: action.sectionId,
        title: action.title,
        createdBy: actorId,
        extra: {
          quantity: action.quantity ?? null,
          unit: action.unit ?? null,
          notes: action.notes ?? null,
          // createTask auto-assigns to createdBy, but that's the assistant's
          // own member row here (see ASSISTANT_EMAIL above) — the household
          // member who actually asked for this isn't who confirmed it, so
          // leave it unassigned rather than showing it "assigned to 🤖".
          assignee_kind: "unassigned",
          assignee_member_id: null,
          assignee_member_ids: [],
        },
      });
      return { createdId: id, undo: () => store.softDeleteTask(id) };
    }
    case "create_section": {
      const id = await store.createSection({
        name: action.name,
        kind: action.kind,
        emoji: action.emoji ?? undefined,
        createdBy: actorId,
      });
      return { createdId: id, undo: () => store.deleteSection(id) };
    }
    case "toggle_task_completed":
      await store.toggleTaskCompleted(action.taskId, actorId);
      // Toggling again flips it right back — safe as long as nothing else
      // touched completion state in between.
      return { undo: () => store.toggleTaskCompleted(action.taskId, actorId) };
    case "move_task": {
      const task = store.tasks[action.taskId];
      const prevSectionId = task?.section_id;
      const prevParentTaskId = task?.parent_task_id ?? null;
      const prevPosition = task?.position;

      const siblings = Object.values(store.tasks).filter(
        (t) => t.section_id === action.sectionId && t.parent_task_id === null && !t.deleted_at
      );
      const lastPosition = siblings.sort((a, b) => (a.position > b.position ? -1 : 1))[0]?.position;
      await store.updateTask(action.taskId, {
        section_id: action.sectionId,
        parent_task_id: null,
        position: rankAtEnd(lastPosition),
      });

      return {
        undo:
          prevSectionId && prevPosition
            ? () =>
                store.updateTask(action.taskId, {
                  section_id: prevSectionId,
                  parent_task_id: prevParentTaskId,
                  position: prevPosition,
                })
            : undefined,
      };
    }
    case "create_chore": {
      // createChore attributes to the currently-acting human device identity
      // rather than an explicit createdBy param (an existing asymmetry with
      // createTask/createSection/createFamilyEvent) — not something this
      // feature reworks.
      const id = await store.createChore({ sectionId: action.sectionId, title: action.title, freq: action.freq });
      return { createdId: id, undo: () => store.deleteChore(id) };
    }
    case "complete_chore":
      if (!actorId) return {};
      await store.completeChore(action.choreId, actorId);
      return {};
    case "create_family_event": {
      const id = await store.createFamilyEvent({
        title: action.title,
        kind: action.kind,
        eventDate: action.eventDate,
        endDate: action.endDate ?? null,
        recurrence: "none",
        createdBy: actorId,
      });
      return { createdId: id, undo: () => store.deleteFamilyEvent(id) };
    }
  }
}

"use client";

import { create } from "zustand";
import { createClient } from "@/lib/supabase/client";
import { useIdentity } from "@/lib/identity";
import { useLocaleStore } from "@/lib/i18n/store";
import { messages } from "@/lib/i18n/messages";
import { enqueueMutation, type QueuedMutation } from "@/lib/offline/db";
import { execGenericWrite } from "@/lib/supabase/generic-write";
import { rankAtEnd, rankBetween } from "@/lib/ordering/rank";
import type {
  Member,
  Section,
  SectionKind,
  Task,
  Chore,
  ChoreCompletion,
  Attachment,
  ActivityLog,
  FamilyEvent,
  AiSuggestion,
  AiPrivateMessage,
} from "@/types/domain";
import { toast } from "sonner";

type ById<T> = Record<string, T>;

type AppState = {
  members: ById<Member>;
  sections: ById<Section>;
  tasks: ById<Task>;
  chores: ById<Chore>;
  choreCompletions: ById<ChoreCompletion>;
  attachments: ById<Attachment>;
  activityLog: ById<ActivityLog>;
  familyEvents: ById<FamilyEvent>;
  aiSuggestions: ById<AiSuggestion>;
  aiPrivateMessages: ById<AiPrivateMessage>;
  hydrated: boolean;

  hydrate: (data: {
    members: Member[];
    sections: Section[];
    tasks: Task[];
    chores: Chore[];
    choreCompletions: ChoreCompletion[];
    attachments: Attachment[];
    activityLog: ActivityLog[];
    familyEvents?: FamilyEvent[];
    aiSuggestions?: AiSuggestion[];
    aiPrivateMessages?: AiPrivateMessage[];
  }) => void;

  applyRemote: (
    table:
      | "members"
      | "sections"
      | "tasks"
      | "chores"
      | "chore_completions"
      | "attachments"
      | "activity_log"
      | "family_events"
      | "ai_suggestions"
      | "ai_private_messages",
    eventType: "INSERT" | "UPDATE" | "DELETE",
    row: Record<string, unknown> | null,
    oldRow: Record<string, unknown> | null
  ) => void;

  updateAiSuggestionStatus: (id: string, status: "applied" | "dismissed") => Promise<void>;
  markPrivateMessageRead: (id: string) => Promise<void>;

  updateMember: (id: string, patch: Partial<Pick<Member, "display_name" | "avatar_emoji" | "avatar_photo_url" | "color">>) => Promise<void>;
  addMember: (input: {
    displayName: string;
    pin: string;
    avatarEmoji: string;
    color: string;
  }) => Promise<{ member: Member } | { error: "pin_taken" | "unknown" }>;

  createSection: (input: { name: string; emoji?: string; kind: SectionKind; createdBy: string | null }) => Promise<string>;
  renameSection: (id: string, name: string, emoji?: string) => Promise<void>;
  updateSectionNote: (id: string, description: string | null) => Promise<void>;
  reorderSection: (id: string, beforeId: string | null, afterId: string | null) => Promise<void>;
  deleteSection: (id: string) => Promise<void>;
  restoreSection: (id: string) => Promise<void>;

  createTask: (input: {
    sectionId: string;
    parentTaskId?: string | null;
    title: string;
    createdBy: string | null;
    extra?: Partial<Task>;
  }) => Promise<string>;
  updateTask: (id: string, patch: Partial<Task>) => Promise<void>;
  toggleTaskCompleted: (id: string, completedBy: string | null) => Promise<void>;
  reorderTask: (id: string, sectionId: string, parentTaskId: string | null, beforeId: string | null, afterId: string | null) => Promise<void>;
  softDeleteTask: (id: string) => Promise<void>;
  restoreTask: (id: string) => Promise<void>;

  createChore: (input: Partial<Chore> & { sectionId: string; title: string; freq: Chore["freq"] }) => Promise<string>;
  updateChore: (id: string, patch: Partial<Chore>) => Promise<void>;
  completeChore: (id: string, completedBy: string) => Promise<void>;
  deleteChore: (id: string) => Promise<void>;
  restoreChore: (id: string) => Promise<void>;

  createFamilyEvent: (input: {
    title: string;
    kind: FamilyEvent["kind"];
    eventDate: string;
    endDate?: string | null;
    recurrence: FamilyEvent["recurrence"];
    emoji?: string | null;
    notes?: string | null;
    createdBy: string | null;
  }) => Promise<string>;
  updateFamilyEvent: (id: string, patch: Partial<FamilyEvent>) => Promise<void>;
  deleteFamilyEvent: (id: string) => Promise<void>;

  sendBroadcastMessage: (message: string, actorId: string | null) => Promise<void>;

  addAttachment: (input: { taskId?: string; choreId?: string; file: File; createdBy: string | null }) => Promise<void>;
  deleteAttachment: (id: string) => Promise<void>;
};

function keyify<T extends { id: string }>(rows: T[]): ById<T> {
  const out: ById<T> = {};
  for (const row of rows) out[row.id] = row;
  return out;
}

/** Merge an incoming row only if it isn't older than what we already have (LWW by updated_at). */
function shouldApply(existing: { updated_at?: string } | undefined, incoming: { updated_at?: string }) {
  if (!existing?.updated_at || !incoming.updated_at) return true;
  return incoming.updated_at >= existing.updated_at;
}

/** Who's acting on this device right now — read directly so callers don't have to thread it through every action. */
function currentActorId(): string | null {
  return useIdentity.getState().actingMemberId;
}

/** Localizes a store-triggered toast against whatever locale is active right
 * now — read directly (like currentActorId) since store actions run outside
 * React and can't call useT(). */
function t(key: keyof (typeof messages)["he"]): string {
  return messages[useLocaleStore.getState().locale][key];
}

/** Tables with an `updated_by` column (fed into the activity_log trigger) — see runMutation. */
const TABLES_WITH_UPDATED_BY = new Set(["sections", "tasks", "chores"]);

/**
 * Runs a write against Supabase. If the device is offline, the mutation is
 * queued in IndexedDB (and replayed in order once connectivity returns, see
 * lib/offline/queue.ts) instead of being attempted and failing — the
 * optimistic state already applied to the store is left standing. If the
 * device is online and the write genuinely fails (validation, RLS, etc.),
 * the caller's rollback runs and an error toast is shown.
 *
 * Update payloads for tables that have an `updated_by` column are stamped
 * with the current identity unless the caller already set one — this is
 * what the DB's activity-log trigger uses to attribute "who changed this",
 * so every update stays attributable without every call site having to
 * remember to pass an actor. Tables without that column (e.g. `members`,
 * which is self-edited, not attributed) are left untouched — stamping an
 * unknown column onto the payload would make PostgREST reject the whole
 * write.
 */
async function runMutation(entry: Omit<QueuedMutation, "seq" | "createdAt">, rollback: () => void, errorMessage: string) {
  if (entry.op === "update" && TABLES_WITH_UPDATED_BY.has(entry.table) && !("updated_by" in entry.payload)) {
    entry = { ...entry, payload: { ...entry.payload, updated_by: currentActorId() } };
  }

  if (typeof navigator !== "undefined" && !navigator.onLine) {
    await enqueueMutation({ ...entry, createdAt: new Date().toISOString() });
    return;
  }

  const supabase = createClient();
  const { error } = await execGenericWrite(supabase, entry);

  if (error) {
    rollback();
    toast.error(errorMessage);
  }
}

export const useAppStore = create<AppState>((set, get) => ({
  members: {},
  sections: {},
  tasks: {},
  chores: {},
  choreCompletions: {},
  attachments: {},
  activityLog: {},
  familyEvents: {},
  aiSuggestions: {},
  aiPrivateMessages: {},
  hydrated: false,

  hydrate: (data) =>
    set({
      members: keyify(data.members),
      sections: keyify(data.sections),
      tasks: keyify(data.tasks),
      chores: keyify(data.chores),
      choreCompletions: keyify(data.choreCompletions),
      attachments: keyify(data.attachments),
      activityLog: keyify(data.activityLog),
      familyEvents: keyify(data.familyEvents ?? []),
      aiSuggestions: keyify(data.aiSuggestions ?? []),
      aiPrivateMessages: keyify(data.aiPrivateMessages ?? []),
      hydrated: true,
    }),

  applyRemote: (table, eventType, row, oldRow) => {
    const map: Record<typeof table, keyof AppState> = {
      members: "members",
      sections: "sections",
      tasks: "tasks",
      chores: "chores",
      chore_completions: "choreCompletions",
      attachments: "attachments",
      activity_log: "activityLog",
      family_events: "familyEvents",
      ai_suggestions: "aiSuggestions",
      ai_private_messages: "aiPrivateMessages",
    };
    const stateKey = map[table] as
      | "members"
      | "sections"
      | "tasks"
      | "chores"
      | "choreCompletions"
      | "attachments"
      | "activityLog"
      | "familyEvents"
      | "aiSuggestions"
      | "aiPrivateMessages";

    set((state) => {
      const bucket = { ...(state[stateKey] as ById<{ id: string; updated_at?: string }>) };

      if (eventType === "DELETE") {
        const id = (oldRow?.id as string) ?? undefined;
        if (id) delete bucket[id];
        return { [stateKey]: bucket } as unknown as Partial<AppState>;
      }

      const incoming = row as unknown as { id: string; updated_at?: string };
      if (!incoming?.id) return {} as Partial<AppState>;
      if (shouldApply(bucket[incoming.id], incoming)) {
        bucket[incoming.id] = incoming;
      }
      return { [stateKey]: bucket } as unknown as Partial<AppState>;
    });
  },

  updateMember: async (id, patch) => {
    const prev = get().members[id];
    set((s) => ({ members: { ...s.members, [id]: { ...s.members[id], ...patch } } }));
    await runMutation(
      { table: "members", op: "update", payload: patch, match: { id } },
      () => prev && set((s) => ({ members: { ...s.members, [id]: prev } })),
      "לא הצלחנו לעדכן את הפרופיל"
    );
  },

  // Adding a member needs an immediate, specific result (was the PIN taken?
  // did it actually work?) to drive the add-member/share-link UI, so — like
  // addAttachment — this talks to Supabase directly instead of going through
  // runMutation/the offline queue, which only ever reports success/failure
  // generically.
  addMember: async ({ displayName, pin, avatarEmoji, color }) => {
    if (Object.values(get().members).some((m) => m.pin === pin)) {
      return { error: "pin_taken" };
    }

    const id = crypto.randomUUID();
    // `email` only ever serves as a unique row key in this app (see
    // 0002_open_access.sql) — there's no email-based auth, so a placeholder
    // is fine as long as it's unique, same as the "yariv@kh.family" seed.
    const email = `member-${id}@kh.family`;

    const supabase = createClient();
    const { data, error } = await supabase
      .from("members")
      .insert({ id, email, display_name: displayName, avatar_emoji: avatarEmoji, color, pin })
      .select()
      .single();

    if (error) {
      return { error: error.code === "23505" ? "pin_taken" : "unknown" };
    }

    set((s) => ({ members: { ...s.members, [id]: data } }));
    return { member: data };
  },

  // ---------------------------------------------------------------------
  // Sections
  // ---------------------------------------------------------------------
  createSection: async ({ name, emoji, kind, createdBy }) => {
    const id = crypto.randomUUID();
    const lastPosition = Object.values(get().sections)
      .filter((s) => !s.deleted_at)
      .sort((a, b) => (a.position > b.position ? -1 : 1))[0]?.position;
    const position = rankAtEnd(lastPosition);
    const now = new Date().toISOString();

    const optimistic: Section = {
      id,
      name,
      emoji: emoji ?? null,
      kind,
      color: null,
      description: null,
      position,
      deleted_at: null,
      created_by: createdBy,
      updated_by: createdBy,
      created_at: now,
      updated_at: now,
    };
    set((s) => ({ sections: { ...s.sections, [id]: optimistic } }));

    await runMutation(
      { table: "sections", op: "insert", payload: { id, name, emoji, kind, position, created_by: createdBy } },
      () =>
        set((s) => {
          const next = { ...s.sections };
          delete next[id];
          return { sections: next };
        }),
      "לא הצלחנו ליצור את הקטגוריה"
    );
    return id;
  },

  renameSection: async (id, name, emoji) => {
    const prev = get().sections[id];
    set((s) => ({ sections: { ...s.sections, [id]: { ...s.sections[id], name, emoji: emoji ?? s.sections[id].emoji } } }));
    await runMutation(
      { table: "sections", op: "update", payload: { name, emoji }, match: { id } },
      () => prev && set((s) => ({ sections: { ...s.sections, [id]: prev } })),
      "לא הצלחנו לשנות את השם"
    );
  },

  updateSectionNote: async (id, description) => {
    const prev = get().sections[id];
    set((s) => ({ sections: { ...s.sections, [id]: { ...s.sections[id], description } } }));
    await runMutation(
      { table: "sections", op: "update", payload: { description }, match: { id } },
      () => prev && set((s) => ({ sections: { ...s.sections, [id]: prev } })),
      "לא הצלחנו לעדכן את ההערה"
    );
  },

  reorderSection: async (id, beforeId, afterId) => {
    const sections = get().sections;
    const position = rankBetween(beforeId ? sections[beforeId]?.position : null, afterId ? sections[afterId]?.position : null);
    const prev = sections[id];
    set((s) => ({ sections: { ...s.sections, [id]: { ...s.sections[id], position } } }));
    await runMutation(
      { table: "sections", op: "update", payload: { position }, match: { id } },
      () => prev && set((s) => ({ sections: { ...s.sections, [id]: prev } })),
      "לא הצלחנו לסדר מחדש"
    );
  },

  deleteSection: async (id) => {
    const now = new Date().toISOString();
    const prev = get().sections[id];
    set((s) => ({ sections: { ...s.sections, [id]: { ...s.sections[id], deleted_at: now } } }));
    await runMutation(
      { table: "sections", op: "update", payload: { deleted_at: now }, match: { id } },
      () => prev && set((s) => ({ sections: { ...s.sections, [id]: prev } })),
      "לא הצלחנו למחוק את הקטגוריה"
    );
    toast(t("sectionDeleted"), {
      action: { label: t("undo"), onClick: () => void get().restoreSection(id) },
    });
  },

  restoreSection: async (id) => {
    const prev = get().sections[id];
    set((s) => ({ sections: { ...s.sections, [id]: { ...s.sections[id], deleted_at: null } } }));
    await runMutation(
      { table: "sections", op: "update", payload: { deleted_at: null }, match: { id } },
      () => prev && set((s) => ({ sections: { ...s.sections, [id]: prev } })),
      "לא הצלחנו לשחזר את הקטגוריה"
    );
  },

  // ---------------------------------------------------------------------
  // Tasks
  // ---------------------------------------------------------------------
  createTask: async ({ sectionId, parentTaskId = null, title, createdBy, extra }) => {
    const id = crypto.randomUUID();
    const siblings = Object.values(get().tasks).filter(
      (t) => t.section_id === sectionId && t.parent_task_id === parentTaskId && !t.deleted_at
    );
    const lastPosition = siblings.sort((a, b) => (a.position > b.position ? -1 : 1))[0]?.position;
    const position = rankAtEnd(lastPosition);
    const now = new Date().toISOString();

    // Whoever adds an item is assigned to it by default — the person typing
    // it in is almost always the one handling it. Notes have no assignee
    // (see task-row.tsx's early return for is_note) so leave those unassigned.
    const isNote = extra?.is_note ?? false;
    const autoAssignee: Pick<Task, "assignee_kind" | "assignee_member_id" | "assignee_member_ids"> =
      createdBy && !isNote
        ? { assignee_kind: "member", assignee_member_id: createdBy, assignee_member_ids: [createdBy] }
        : { assignee_kind: "unassigned", assignee_member_id: null, assignee_member_ids: [] };

    const optimistic: Task = {
      id,
      section_id: sectionId,
      parent_task_id: parentTaskId,
      position,
      title,
      notes: null,
      emoji: null,
      priority: null,
      due_at: null,
      due_end_at: null,
      due_notified_at: null,
      recurrence: null,
      tags: [],
      detected_links: [],
      is_note: false,
      ...autoAssignee,
      is_completed: false,
      completed_at: null,
      completed_by: null,
      quantity: null,
      unit: null,
      price: null,
      currency: "ILS",
      brand: null,
      image_url: null,
      deleted_at: null,
      created_by: createdBy,
      updated_by: createdBy,
      created_at: now,
      updated_at: now,
      ...extra,
    };
    set((s) => ({ tasks: { ...s.tasks, [id]: optimistic } }));

    await runMutation(
      {
        table: "tasks",
        op: "insert",
        payload: { id, section_id: sectionId, parent_task_id: parentTaskId, position, title, created_by: createdBy, ...autoAssignee, ...extra },
      },
      () =>
        set((s) => {
          const next = { ...s.tasks };
          delete next[id];
          return { tasks: next };
        }),
      "לא הצלחנו ליצור את המשימה"
    );
    return id;
  },

  updateTask: async (id, patch) => {
    const prev = get().tasks[id];
    set((s) => ({ tasks: { ...s.tasks, [id]: { ...s.tasks[id], ...patch } } }));
    await runMutation(
      { table: "tasks", op: "update", payload: patch, match: { id } },
      () => prev && set((s) => ({ tasks: { ...s.tasks, [id]: prev } })),
      "לא הצלחנו לעדכן את המשימה"
    );
  },

  toggleTaskCompleted: async (id, completedBy) => {
    const task = get().tasks[id];
    if (!task) return;
    const willComplete = !task.is_completed;
    await get().updateTask(id, {
      is_completed: willComplete,
      completed_at: willComplete ? new Date().toISOString() : null,
      completed_by: willComplete ? completedBy : null,
    });
  },

  reorderTask: async (id, sectionId, parentTaskId, beforeId, afterId) => {
    const tasks = get().tasks;
    const position = rankBetween(beforeId ? tasks[beforeId]?.position : null, afterId ? tasks[afterId]?.position : null);
    const prev = tasks[id];
    set((s) => ({
      tasks: { ...s.tasks, [id]: { ...s.tasks[id], section_id: sectionId, parent_task_id: parentTaskId, position } },
    }));
    await runMutation(
      { table: "tasks", op: "update", payload: { section_id: sectionId, parent_task_id: parentTaskId, position }, match: { id } },
      () => prev && set((s) => ({ tasks: { ...s.tasks, [id]: prev } })),
      "לא הצלחנו לסדר מחדש"
    );
  },

  softDeleteTask: async (id) => {
    const now = new Date().toISOString();
    const affected = Object.values(get().tasks).filter((t) => t.id === id || isDescendant(get().tasks, t, id));
    const prevValues = affected.map((t) => [t.id, t] as const);
    set((s) => {
      const next = { ...s.tasks };
      for (const t of affected) next[t.id] = { ...t, deleted_at: now };
      return { tasks: next };
    });
    await runMutation(
      { table: "tasks", op: "rpc", rpcName: "soft_delete_task", payload: { p_task_id: id, p_actor_id: currentActorId() } },
      () =>
        set((s) => {
          const next = { ...s.tasks };
          for (const [tid, t] of prevValues) next[tid] = t;
          return { tasks: next };
        }),
      "לא הצלחנו למחוק את המשימה"
    );
    toast(t("taskDeleted"), {
      action: { label: t("undo"), onClick: () => get().restoreTask(id) },
    });
  },

  restoreTask: async (id) => {
    const affected = Object.values(get().tasks).filter((t) => t.deleted_at && (t.id === id || isDescendant(get().tasks, t, id)));
    const prevValues = affected.map((t) => [t.id, t] as const);
    set((s) => {
      const next = { ...s.tasks };
      for (const t of affected) next[t.id] = { ...t, deleted_at: null };
      return { tasks: next };
    });
    await runMutation(
      { table: "tasks", op: "rpc", rpcName: "restore_task", payload: { p_task_id: id, p_actor_id: currentActorId() } },
      () =>
        set((s) => {
          const next = { ...s.tasks };
          for (const [tid, t] of prevValues) next[tid] = t;
          return { tasks: next };
        }),
      "לא הצלחנו לשחזר את המשימה"
    );
  },

  // ---------------------------------------------------------------------
  // Chores
  // ---------------------------------------------------------------------
  createChore: async (input) => {
    const id = crypto.randomUUID();
    const actorId = currentActorId();
    const siblings = Object.values(get().chores).filter((c) => c.section_id === input.sectionId && !c.deleted_at);
    const lastPosition = siblings.sort((a, b) => (a.position > b.position ? -1 : 1))[0]?.position;
    const position = rankAtEnd(lastPosition);
    const now = new Date().toISOString();

    const optimistic: Chore = {
      id,
      section_id: input.sectionId,
      title: input.title,
      notes: input.notes ?? null,
      emoji: input.emoji ?? null,
      position,
      assignee_member_id: input.assignee_member_id ?? null,
      assignee_member_ids: input.assignee_member_ids ?? [],
      assignee_kind: input.assignee_kind ?? "anyone",
      freq: input.freq,
      interval_n: input.interval_n ?? 1,
      weekdays: input.weekdays ?? null,
      month_day: input.month_day ?? null,
      custom_cron: input.custom_cron ?? null,
      anchor_date: input.anchor_date ?? now.slice(0, 10),
      next_due_at: input.next_due_at ?? now,
      deleted_at: null,
      created_by: actorId,
      updated_by: actorId,
      created_at: now,
      updated_at: now,
    };
    set((s) => ({ chores: { ...s.chores, [id]: optimistic } }));

    await runMutation(
      {
        table: "chores",
        op: "insert",
        payload: {
          id,
          section_id: input.sectionId,
          title: input.title,
          freq: input.freq,
          position,
          created_by: actorId,
          assignee_kind: optimistic.assignee_kind,
          assignee_member_id: optimistic.assignee_member_id,
          assignee_member_ids: optimistic.assignee_member_ids,
          weekdays: optimistic.weekdays,
          emoji: optimistic.emoji,
        },
      },
      () =>
        set((s) => {
          const next = { ...s.chores };
          delete next[id];
          return { chores: next };
        }),
      "לא הצלחנו ליצור את המטלה"
    );
    return id;
  },

  updateChore: async (id, patch) => {
    const prev = get().chores[id];
    set((s) => ({ chores: { ...s.chores, [id]: { ...s.chores[id], ...patch } } }));
    await runMutation(
      { table: "chores", op: "update", payload: patch, match: { id } },
      () => prev && set((s) => ({ chores: { ...s.chores, [id]: prev } })),
      "לא הצלחנו לעדכן את המטלה"
    );
  },

  completeChore: async (id, completedBy) => {
    const prev = get().chores[id];
    // Optimistically bump next_due_at forward by a day so the UI reflects "done for now";
    // the RPC computes the real next occurrence and the realtime echo corrects it.
    set((s) => ({
      chores: {
        ...s.chores,
        [id]: { ...s.chores[id], next_due_at: new Date(Date.now() + 86400000).toISOString() },
      },
    }));
    await runMutation(
      { table: "chores", op: "rpc", rpcName: "complete_chore", payload: { p_chore_id: id, p_completed_by: completedBy } },
      () => prev && set((s) => ({ chores: { ...s.chores, [id]: prev } })),
      "לא הצלחנו לסמן את המטלה כבוצעה"
    );
  },

  deleteChore: async (id) => {
    const now = new Date().toISOString();
    const prev = get().chores[id];
    set((s) => ({ chores: { ...s.chores, [id]: { ...s.chores[id], deleted_at: now } } }));
    await runMutation(
      { table: "chores", op: "update", payload: { deleted_at: now }, match: { id } },
      () => prev && set((s) => ({ chores: { ...s.chores, [id]: prev } })),
      "לא הצלחנו למחוק את המטלה"
    );
    toast(t("choreDeleted"), {
      action: { label: t("undo"), onClick: () => void get().restoreChore(id) },
    });
  },

  restoreChore: async (id) => {
    const prev = get().chores[id];
    set((s) => ({ chores: { ...s.chores, [id]: { ...s.chores[id], deleted_at: null } } }));
    await runMutation(
      { table: "chores", op: "update", payload: { deleted_at: null }, match: { id } },
      () => prev && set((s) => ({ chores: { ...s.chores, [id]: prev } })),
      "לא הצלחנו לשחזר את המטלה"
    );
  },

  // ---------------------------------------------------------------------
  // Family events
  // ---------------------------------------------------------------------
  createFamilyEvent: async ({ title, kind, eventDate, endDate, recurrence, emoji, notes, createdBy }) => {
    const id = crypto.randomUUID();
    const now = new Date().toISOString();

    const optimistic: FamilyEvent = {
      id,
      title,
      kind,
      emoji: emoji ?? null,
      event_date: eventDate,
      end_date: endDate ?? null,
      recurrence,
      notes: notes ?? null,
      last_notified_on: null,
      deleted_at: null,
      created_by: createdBy,
      updated_by: createdBy,
      created_at: now,
      updated_at: now,
    };
    set((s) => ({ familyEvents: { ...s.familyEvents, [id]: optimistic } }));

    await runMutation(
      {
        table: "family_events",
        op: "insert",
        payload: {
          id,
          title,
          kind,
          emoji: optimistic.emoji,
          event_date: eventDate,
          end_date: optimistic.end_date,
          recurrence,
          notes: optimistic.notes,
          created_by: createdBy,
        },
      },
      () =>
        set((s) => {
          const next = { ...s.familyEvents };
          delete next[id];
          return { familyEvents: next };
        }),
      "לא הצלחנו ליצור את האירוע"
    );
    return id;
  },

  updateFamilyEvent: async (id, patch) => {
    const prev = get().familyEvents[id];
    set((s) => ({ familyEvents: { ...s.familyEvents, [id]: { ...s.familyEvents[id], ...patch } } }));
    await runMutation(
      { table: "family_events", op: "update", payload: patch, match: { id } },
      () => prev && set((s) => ({ familyEvents: { ...s.familyEvents, [id]: prev } })),
      "לא הצלחנו לעדכן את האירוע"
    );
  },

  deleteFamilyEvent: async (id) => {
    const now = new Date().toISOString();
    const prev = get().familyEvents[id];
    set((s) => ({ familyEvents: { ...s.familyEvents, [id]: { ...s.familyEvents[id], deleted_at: now } } }));
    await runMutation(
      { table: "family_events", op: "update", payload: { deleted_at: now }, match: { id } },
      () => prev && set((s) => ({ familyEvents: { ...s.familyEvents, [id]: prev } })),
      "לא הצלחנו למחוק את האירוע"
    );
  },

  // ---------------------------------------------------------------------
  // Broadcast messages — a one-off activity_log row with no backing entity,
  // fanned out to every device through the same trigger/edge-function path
  // as every other activity_log insert (see supabase/functions/send-push).
  // ---------------------------------------------------------------------
  sendBroadcastMessage: async (message, actorId) => {
    await runMutation(
      {
        table: "activity_log",
        op: "insert",
        payload: { entity_type: "broadcast", entity_id: crypto.randomUUID(), action: "message", actor_id: actorId, summary: message },
      },
      () => {},
      "לא הצלחנו לשלוח את ההודעה"
    );
  },

  // ---------------------------------------------------------------------
  // AI suggestions (see supabase/functions/assistant's "insights" mode) —
  // a suggestion is only ever marked applied/dismissed here; actually
  // *applying* one runs through applyProposedAction, same as a chat action.
  // ---------------------------------------------------------------------
  updateAiSuggestionStatus: async (id, status) => {
    const prev = get().aiSuggestions[id];
    set((s) => ({ aiSuggestions: { ...s.aiSuggestions, [id]: { ...s.aiSuggestions[id], status } } }));
    await runMutation(
      { table: "ai_suggestions", op: "update", payload: { status }, match: { id } },
      () => prev && set((s) => ({ aiSuggestions: { ...s.aiSuggestions, [id]: prev } })),
      "לא הצלחנו לעדכן את ההצעה"
    );
  },

  // ---------------------------------------------------------------------
  // Mika's personal one-on-one notes (see supabase/functions/assistant's
  // "personal_checkin" mode + migration 0026's ai_private_messages table) —
  // dismissing one just marks it read; there's nothing to "apply".
  // ---------------------------------------------------------------------
  markPrivateMessageRead: async (id) => {
    const prev = get().aiPrivateMessages[id];
    const now = new Date().toISOString();
    set((s) => ({ aiPrivateMessages: { ...s.aiPrivateMessages, [id]: { ...s.aiPrivateMessages[id], read_at: now } } }));
    await runMutation(
      { table: "ai_private_messages", op: "update", payload: { read_at: now }, match: { id } },
      () => prev && set((s) => ({ aiPrivateMessages: { ...s.aiPrivateMessages, [id]: prev } })),
      "לא הצלחנו לסמן את ההודעה כנקראה"
    );
  },

  // ---------------------------------------------------------------------
  // Attachments — a real file upload, not a queueable payload, so this
  // talks to Supabase directly rather than through runMutation/the offline
  // queue (matches how the avatar photo upload works in profile-edit-dialog).
  // ---------------------------------------------------------------------
  addAttachment: async ({ taskId, choreId, file, createdBy }) => {
    const supabase = createClient();
    const id = crypto.randomUUID();
    const storagePath = `${taskId ?? choreId}/${id}-${file.name}`;

    const { error: uploadError } = await supabase.storage.from("attachments").upload(storagePath, file);
    if (uploadError) {
      toast.error("לא הצלחנו להעלות את הקובץ");
      return;
    }

    const attachment: Attachment = {
      id,
      task_id: taskId ?? null,
      chore_id: choreId ?? null,
      storage_path: storagePath,
      file_name: file.name,
      mime_type: file.type || null,
      size_bytes: file.size,
      kind: attachmentKindFor(file.type),
      width: null,
      height: null,
      created_by: createdBy,
      created_at: new Date().toISOString(),
    };

    const { error: insertError } = await supabase.from("attachments").insert(attachment);
    if (insertError) {
      await supabase.storage.from("attachments").remove([storagePath]);
      toast.error("לא הצלחנו לשמור את הקובץ");
      return;
    }

    set((s) => ({ attachments: { ...s.attachments, [id]: attachment } }));
  },

  deleteAttachment: async (id) => {
    const attachment = get().attachments[id];
    if (!attachment) return;
    set((s) => {
      const next = { ...s.attachments };
      delete next[id];
      return { attachments: next };
    });

    const supabase = createClient();
    await supabase.storage.from("attachments").remove([attachment.storage_path]);
    const { error } = await supabase.from("attachments").delete().eq("id", id);
    if (error) {
      set((s) => ({ attachments: { ...s.attachments, [id]: attachment } }));
      toast.error("לא הצלחנו למחוק את הקובץ");
    }
  },
}));

function attachmentKindFor(mimeType: string): Attachment["kind"] {
  if (mimeType.startsWith("image/")) return "image";
  if (mimeType === "application/pdf") return "pdf";
  if (mimeType.startsWith("audio/")) return "audio";
  if (mimeType.startsWith("video/")) return "video";
  return "file";
}

function isDescendant(tasks: ById<Task>, candidate: Task, ancestorId: string): boolean {
  let current: Task | undefined = candidate;
  const seen = new Set<string>();
  while (current?.parent_task_id) {
    if (seen.has(current.id)) return false;
    seen.add(current.id);
    if (current.parent_task_id === ancestorId) return true;
    current = tasks[current.parent_task_id];
  }
  return false;
}

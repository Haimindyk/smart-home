import type { Tables } from "./database";

export type Member = Tables<"members">;

export type SectionKind = "tasks" | "shopping" | "chores" | "info";
export type Section = Omit<Tables<"sections">, "kind"> & { kind: SectionKind };

export type AssigneeKind = "unassigned" | "member" | "anyone" | "louis";
export type Task = Omit<Tables<"tasks">, "assignee_kind" | "recurrence"> & {
  assignee_kind: AssigneeKind;
  recurrence: { freq?: string } | null;
};

export type ChoreFreq = "daily" | "weekly" | "monthly" | "custom" | "as_needed";
export type ChoreAssigneeKind = "member" | "anyone" | "louis";
export type Chore = Omit<Tables<"chores">, "freq" | "assignee_kind"> & {
  freq: ChoreFreq;
  assignee_kind: ChoreAssigneeKind;
};

export type ChoreCompletion = Tables<"chore_completions">;
export type Attachment = Tables<"attachments">;
export type ActivityLog = Tables<"activity_log">;
export type PushSubscriptionRow = Tables<"push_subscriptions">;
export type NotificationPrefs = Tables<"notification_prefs">;
export type BarcodeProduct = Tables<"barcode_products">;

export type EventKind = "birthday" | "medical" | "other";
export type EventRecurrence = "none" | "yearly";
export type FamilyEvent = Omit<Tables<"family_events">, "kind" | "recurrence"> & {
  kind: EventKind;
  recurrence: EventRecurrence;
};

/** A task with its children materialized into a tree (client-side only). */
export type TaskNode = Task & { children: TaskNode[] };

export function buildTaskTree(tasks: Task[]): TaskNode[] {
  const byParent = new Map<string | null, Task[]>();
  for (const task of tasks) {
    const key = task.parent_task_id;
    const list = byParent.get(key) ?? [];
    list.push(task);
    byParent.set(key, list);
  }
  for (const list of byParent.values()) {
    list.sort((a, b) => (a.position < b.position ? -1 : a.position > b.position ? 1 : 0));
  }

  function attach(parentId: string | null): TaskNode[] {
    const children = byParent.get(parentId) ?? [];
    return children.map((task) => ({ ...task, children: attach(task.id) }));
  }

  return attach(null);
}

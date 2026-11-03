import { openDB, type IDBPDatabase } from "idb";

const DB_NAME = "kh-offline";
const DB_VERSION = 2;
const SNAPSHOT_STORE = "snapshot";
const QUEUE_STORE = "mutation-queue";

let dbPromise: Promise<IDBPDatabase> | undefined;

function getDb() {
  dbPromise ??= openDB(DB_NAME, DB_VERSION, {
    upgrade(db, oldVersion, _newVersion, tx) {
      if (oldVersion === 1) {
        tx.objectStore(SNAPSHOT_STORE).clear();
        tx.objectStore(QUEUE_STORE).clear();
      }
      if (!db.objectStoreNames.contains(SNAPSHOT_STORE)) {
        db.createObjectStore(SNAPSHOT_STORE);
      }
      if (!db.objectStoreNames.contains(QUEUE_STORE)) {
        db.createObjectStore(QUEUE_STORE, {
          keyPath: "seq",
          autoIncrement: true,
        });
      }
    },
  });
  return dbPromise;
}

/** The full hydrated dataset, cached so the app opens instantly offline. */
export async function saveSnapshot(data: unknown) {
  const db = await getDb();
  const snapshot = data as { members?: Record<string, unknown>[] };
  const safe = snapshot?.members
    ? {
        ...snapshot,
        members: snapshot.members.map((member) => ({ ...member, pin: null })),
      }
    : data;
  await db.put(SNAPSHOT_STORE, safe, "all");
}

export async function loadSnapshot<T>(): Promise<T | undefined> {
  const db = await getDb();
  return db.get(SNAPSHOT_STORE, "all");
}

export type MutableTable =
  | "members"
  | "sections"
  | "tasks"
  | "chores"
  | "chore_completions"
  | "attachments"
  | "family_events"
  | "activity_log"
  | "ai_suggestions"
  | "ai_private_messages";

export type QueuedMutation = {
  seq?: number;
  table: MutableTable;
  op: "insert" | "update" | "rpc";
  payload: Record<string, unknown>;
  match?: Record<string, unknown>;
  rpcName?: string;
  createdAt: string;
};

export async function enqueueMutation(mutation: Omit<QueuedMutation, "seq">) {
  const db = await getDb();
  await db.add(QUEUE_STORE, mutation);
}

export async function listQueuedMutations(): Promise<QueuedMutation[]> {
  const db = await getDb();
  return db.getAll(QUEUE_STORE);
}

export async function removeQueuedMutation(seq: number) {
  const db = await getDb();
  await db.delete(QUEUE_STORE, seq);
}

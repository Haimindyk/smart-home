import { openDB, type IDBPDatabase } from "idb";

const DB_NAME = "kh-offline";
const DB_VERSION = 1;
const SNAPSHOT_STORE = "snapshot";
const QUEUE_STORE = "mutation-queue";

let dbPromise: Promise<IDBPDatabase> | undefined;

function getDb() {
  dbPromise ??= openDB(DB_NAME, DB_VERSION, {
    upgrade(db) {
      if (!db.objectStoreNames.contains(SNAPSHOT_STORE)) {
        db.createObjectStore(SNAPSHOT_STORE);
      }
      if (!db.objectStoreNames.contains(QUEUE_STORE)) {
        db.createObjectStore(QUEUE_STORE, { keyPath: "seq", autoIncrement: true });
      }
    },
  });
  return dbPromise;
}

/** The full hydrated dataset, cached so the app opens instantly offline. */
export async function saveSnapshot(data: unknown) {
  const db = await getDb();
  await db.put(SNAPSHOT_STORE, data, "all");
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

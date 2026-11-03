import { openDB } from "idb";
import type { HealthData, HealthTable, HealthRow } from "./model";
export type HealthMutation = {
  id: string;
  seq?: number;
  owner: string;
  table: HealthTable;
  row: HealthRow;
  expectedVersion: number | null;
  createdAt: string;
};
const db = () =>
  openDB("kh-health-private-v1", 1, {
    upgrade(d) {
      d.createObjectStore("snapshots");
      const queue = d.createObjectStore("queue", {
        keyPath: "seq",
        autoIncrement: true,
      });
      queue.createIndex("id", "id", { unique: true });
    },
  });
export async function readHealthCache(
  owner: string,
): Promise<HealthData | undefined> {
  return (await db()).get("snapshots", owner);
}
export async function writeHealthCache(owner: string, data: HealthData) {
  await (await db()).put("snapshots", data, owner);
}
export async function queueHealthMutation(m: HealthMutation) {
  const d = await db();
  const tx = d.transaction("queue", "readwrite");
  const existing = await tx.store.index("id").get(m.id);
  await tx.store.put(existing ? { ...m, seq: existing.seq } : m);
  await tx.done;
}
export async function pendingHealthMutations(
  owner: string,
): Promise<HealthMutation[]> {
  return ((await (await db()).getAll("queue")) as HealthMutation[])
    .filter((m) => m.owner === owner)
    .sort((a, b) => (a.seq ?? 0) - (b.seq ?? 0));
}
export async function removeHealthMutation(id: string) {
  const d = await db();
  const tx = d.transaction("queue", "readwrite");
  const key = await tx.store.index("id").getKey(id);
  if (key !== undefined) await tx.store.delete(key);
  await tx.done;
}
export async function clearPrivateCache() {
  const d = await db();
  const tx = d.transaction(["snapshots", "queue"], "readwrite");
  await Promise.all([
    tx.objectStore("snapshots").clear(),
    tx.objectStore("queue").clear(),
  ]);
  await tx.done;
}

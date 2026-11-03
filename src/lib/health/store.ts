"use client";
import { create } from "zustand";
import { healthClient } from "./database";
import {
  healthTables,
  emptyHealthData,
  payloadSchemas,
  type HealthData,
  type HealthRow,
  type HealthTable,
  type Payload,
} from "./model";
import {
  clearPrivateCache,
  pendingHealthMutations,
  queueHealthMutation,
  readHealthCache,
  removeHealthMutation,
  writeHealthCache,
  type HealthMutation,
} from "./offline";
import { useIdentity } from "@/lib/identity";

type State = {
  owner: string | null;
  data: HealthData;
  loading: boolean;
  error: string | null;
  pending: number;
  conflict: HealthMutation | null;
  boot: () => Promise<void>;
  refresh: () => Promise<void>;
  flush: () => Promise<void>;
  reset: () => Promise<void>;
  save: <T extends HealthTable>(
    table: T,
    data: Payload<T>,
    existing?: HealthRow<T>,
    id?: string,
  ) => Promise<HealthRow<T>>;
  remove: <T extends HealthTable>(table: T, row: HealthRow<T>) => Promise<void>;
  resolveConflict: (keepLocal: boolean) => Promise<void>;
};
async function authenticatedOwner(allowCached = false) {
  const supabase = healthClient();
  if (allowCached && !navigator.onLine) {
    const {
      data: { session },
    } = await supabase.auth.getSession();
    const identity = JSON.parse(
      localStorage.getItem("kh-auth-owner") ?? "null",
    );
    if (
      session &&
      session.expires_at &&
      session.expires_at * 1000 > Date.now() &&
      identity?.userId === session.user.id &&
      identity?.memberId === useIdentity.getState().actingMemberId
    )
      return session.user.id;
    throw new Error("session_required");
  }
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();
  if (error || !user) throw new Error("session_required");
  const { data: member } = await supabase
    .from("members")
    .select("id")
    .eq("user_id", user.id)
    .maybeSingle();
  if (!member || member.id !== useIdentity.getState().actingMemberId)
    throw new Error("session_mismatch");
  return user.id;
}
function message(e: unknown) {
  return e instanceof Error ? e.message : "sync_failed";
}
async function send(m: HealthMutation) {
  if ((await authenticatedOwner()) !== m.owner)
    throw new Error("session_mismatch");
  const c = healthClient();
  if (m.expectedVersion === null) {
    const { error } = await c.from(m.table).insert({
      id: m.row.id,
      owner_user_id: m.owner,
      data: m.row.data,
      last_mutation_id: m.id,
    });
    if (error && error.code !== "23505") throw new Error(error.message);
    // Duplicate insert is an idempotent retry only if the same row is ours.
    const { data, error: readError } = await c
      .from(m.table)
      .select("*")
      .eq("id", m.row.id)
      .single();
    if (readError || !data)
      throw new Error(readError?.message ?? "sync_failed");
    if (data.last_mutation_id !== m.id) throw new Error("version_conflict");
    return data as HealthRow;
  }
  const { data, error } = await c
    .from(m.table)
    .update({
      data: m.row.data,
      version: m.expectedVersion + 1,
      deleted_at: m.row.deleted_at,
      last_mutation_id: m.id,
    })
    .eq("id", m.row.id)
    .eq("version", m.expectedVersion)
    .select()
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!data) {
    const { data: current } = await c
      .from(m.table)
      .select("*")
      .eq("id", m.row.id)
      .maybeSingle();
    if (
      current &&
      current.version === m.expectedVersion + 1 &&
      current.last_mutation_id === m.id &&
      current.deleted_at === m.row.deleted_at
    )
      return current as HealthRow;
    throw new Error("version_conflict");
  }
  return data as HealthRow;
}
function replaceRow(
  data: HealthData,
  table: HealthTable,
  row: HealthRow,
): HealthData {
  return {
    ...data,
    [table]: [...data[table].filter((r) => r.id !== row.id), row].filter(
      (r) => !r.deleted_at,
    ),
  };
}
export const useHealthStore = create<State>((set, get) => ({
  owner: null,
  data: emptyHealthData(),
  loading: true,
  error: null,
  pending: 0,
  conflict: null,
  reset: async () => {
    generation++;
    for (const key of Object.keys(sessionStorage))
      if (key.startsWith("kh-health-draft:")) sessionStorage.removeItem(key);
    set({
      owner: null,
      data: emptyHealthData(),
      loading: true,
      error: null,
      pending: 0,
      conflict: null,
    });
    await clearPrivateCache();
  },
  boot: async () => {
    const epoch = generation;
    set({ loading: true, error: null });
    try {
      const owner = await authenticatedOwner(true);
      if (generation !== epoch) return;
      if (get().owner && get().owner !== owner) {
        await get().reset();
        return get().boot();
      }
      set({ owner });
      const cached = await readHealthCache(owner);
      if (cached && get().owner === owner) set({ data: cached });
      await get().flush();
      await get().refresh();
    } catch (e) {
      if (generation === epoch) set({ error: message(e) });
    } finally {
      if (generation === epoch) set({ loading: false });
    }
  },
  refresh: async () => {
    const owner = get().owner;
    const epoch = generation;
    if (!owner || !navigator.onLine) return;
    try {
      if ((await authenticatedOwner()) !== owner) return;
      const c = healthClient();
      const results = await Promise.all(
        healthTables.map(async (table) => {
          const rows: HealthRow[] = [];
          for (let offset = 0; ; offset += 500) {
            const { data, error } = await c
              .from(table)
              .select("*")
              .is("deleted_at", null)
              .order("created_at")
              .order("id")
              .range(offset, offset + 499);
            if (error) throw new Error(error.message);
            rows.push(...(data as HealthRow[]));
            if (data.length < 500) break;
          }
          return [table, rows];
        }),
      );
      if (get().owner !== owner || generation !== epoch) return;
      let data = Object.fromEntries(results) as HealthData;
      const queued = await pendingHealthMutations(owner);
      if (get().owner !== owner || generation !== epoch) return;
      for (const m of queued) data = replaceRow(data, m.table, m.row);
      set({ data, error: null, pending: queued.length });
      await writeHealthCache(owner, data);
    } catch (e) {
      set({ error: message(e) });
    }
  },
  save: async (table, data, existing, id) => {
    const owner = get().owner;
    if (!owner) throw new Error("session_required");
    const parsed = payloadSchemas[table].parse(data);
    if (existing && existing.owner_user_id !== owner)
      throw new Error("session_mismatch");
    const now = new Date().toISOString();
    const row = {
      id: id ?? existing?.id ?? crypto.randomUUID(),
      owner_user_id: owner,
      data: parsed,
      version: existing ? existing.version + 1 : 1,
      created_at: existing?.created_at ?? now,
      updated_at: now,
      deleted_at: null,
    } as HealthRow;
    const m: HealthMutation = {
      id: crypto.randomUUID(),
      owner,
      table,
      row,
      expectedVersion: existing?.version ?? null,
      createdAt: now,
    };
    await queueHealthMutation(m);
    if (get().owner !== owner) throw new Error("session_mismatch");
    const next = replaceRow(get().data, table, row);
    set({ data: next, pending: get().pending + 1 });
    await writeHealthCache(owner, next);
    await get().flush();
    return row as HealthRow<typeof table>;
  },
  remove: async (table, row) => {
    const owner = get().owner;
    if (!owner || row.owner_user_id !== owner)
      throw new Error("session_mismatch");
    const now = new Date().toISOString();
    const m: HealthMutation = {
      id: crypto.randomUUID(),
      owner,
      table,
      row: { ...row, deleted_at: now, version: row.version + 1 },
      expectedVersion: row.version,
      createdAt: now,
    };
    await queueHealthMutation(m);
    if (get().owner !== owner) throw new Error("session_mismatch");
    const data = replaceRow(get().data, table, m.row);
    set({ data, pending: get().pending + 1 });
    await writeHealthCache(owner, data);
    await get().flush();
  },
  flush: async () => {
    await flushSerialized();
  },
  resolveConflict: async (keepLocal) => {
    const m = get().conflict;
    if (!m || m.owner !== get().owner) return;
    const { data: current, error } = await healthClient()
      .from(m.table)
      .select("*")
      .eq("id", m.row.id)
      .single();
    if (error || !current) {
      if (keepLocal) throw new Error("sync_failed");
      for (const pending of await pendingHealthMutations(m.owner))
        if (pending.row.id === m.row.id) await removeHealthMutation(pending.id);
      set({ conflict: null, error: null });
      await get().refresh();
      return;
    }
    if (keepLocal)
      await queueHealthMutation({
        ...m,
        expectedVersion: current.version,
        row: { ...m.row, version: current.version + 1 },
      });
    else
      for (const pending of await pendingHealthMutations(m.owner))
        if (pending.row.id === m.row.id) await removeHealthMutation(pending.id);
    set({ conflict: null, error: null });
    await get().flush();
    await get().refresh();
  },
}));
let generation = 0;
let activeFlush: Promise<void> | null = null;
function flushSerialized() {
  if (activeFlush) return activeFlush;
  activeFlush = (async () => {
    const owner = useHealthStore.getState().owner;
    if (!owner || !navigator.onLine) return;
    while (true) {
      const m = (await pendingHealthMutations(owner))[0];
      if (!m) break;
      if (useHealthStore.getState().owner !== owner) return;
      try {
        const row = await send(m);
        await removeHealthMutation(m.id);
        if (useHealthStore.getState().owner !== owner) return;
        // Later queued edits must keep their optimistic state until they are sent.
        const queued = await pendingHealthMutations(owner);
        if (useHealthStore.getState().owner !== owner) return;
        let data = replaceRow(useHealthStore.getState().data, m.table, row);
        for (const q of queued) data = replaceRow(data, q.table, q.row);
        useHealthStore.setState({ data, pending: queued.length, error: null });
        await writeHealthCache(owner, data);
      } catch (e) {
        if (useHealthStore.getState().owner !== owner) return;
        const error = message(e);
        useHealthStore.setState({
          error,
          conflict: m,
        });
        break;
      }
    }
  })().finally(() => {
    activeFlush = null;
  });
  return activeFlush;
}

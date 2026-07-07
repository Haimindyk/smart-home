import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";
import type { QueuedMutation } from "@/lib/offline/db";

/**
 * Dispatches a table-agnostic write (insert/update/rpc) against Supabase.
 * Supabase-js's generated types are intentionally per-table exact, which
 * fights a generic "replay whatever mutation was queued" dispatcher — this
 * is the one place that trades that type safety for a single reusable path
 * shared by optimistic writes (app-store.ts) and offline replay (queue.ts).
 */
export async function execGenericWrite(
  supabase: SupabaseClient<Database>,
  mutation: Pick<QueuedMutation, "table" | "op" | "payload" | "match" | "rpcName">
) {
  if (mutation.op === "insert") {
    return supabase.from(mutation.table).insert(mutation.payload as never);
  }
  if (mutation.op === "update") {
    return supabase
      .from(mutation.table)
      .update(mutation.payload as never)
      .match(mutation.match ?? {});
  }
  return supabase.rpc(mutation.rpcName as never, mutation.payload as never);
}

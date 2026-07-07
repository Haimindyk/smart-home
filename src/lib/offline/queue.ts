import { createClient } from "@/lib/supabase/client";
import { execGenericWrite } from "@/lib/supabase/generic-write";
import { listQueuedMutations, removeQueuedMutation } from "./db";

/** Replays queued offline mutations in order (FIFO) once connectivity returns. */
export async function flushMutationQueue() {
  const queued = await listQueuedMutations();
  if (queued.length === 0) return;

  const supabase = createClient();
  for (const mutation of queued.sort((a, b) => (a.seq ?? 0) - (b.seq ?? 0))) {
    const { error } = await execGenericWrite(supabase, mutation);
    // A row that no longer exists (already deleted elsewhere) is fine to drop silently.
    if (!error || error.code === "PGRST116") {
      if (mutation.seq !== undefined) await removeQueuedMutation(mutation.seq);
    } else {
      // Stop at the first real failure so later mutations (which may depend on
      // this one) aren't applied out of order; they'll retry on the next flush.
      break;
    }
  }
}

"use client";

import { useEffect } from "react";
import { createClient } from "@/lib/supabase/client";
import { useAppStore } from "@/lib/store/app-store";
import { loadSnapshot, saveSnapshot } from "@/lib/offline/db";
import { flushMutationQueue } from "@/lib/offline/queue";
import type { Member, Section, Task, Chore, ChoreCompletion, Attachment, ActivityLog } from "@/types/domain";

type Snapshot = {
  members: Member[];
  sections: Section[];
  tasks: Task[];
  chores: Chore[];
  choreCompletions: ChoreCompletion[];
  attachments: Attachment[];
  activityLog: ActivityLog[];
};

const TABLES = ["members", "sections", "tasks", "chores", "chore_completions", "attachments", "activity_log"] as const;

async function fetchAll(): Promise<Snapshot> {
  const supabase = createClient();
  const [members, sections, tasks, chores, choreCompletions, attachments, activityLog] = await Promise.all([
    supabase.from("members").select("*"),
    supabase.from("sections").select("*").order("position"),
    supabase.from("tasks").select("*").order("position"),
    supabase.from("chores").select("*").order("position"),
    supabase.from("chore_completions").select("*"),
    supabase.from("attachments").select("*"),
    supabase.from("activity_log").select("*").order("created_at", { ascending: false }).limit(200),
  ]);
  return {
    members: (members.data ?? []) as Member[],
    sections: (sections.data ?? []) as Section[],
    tasks: (tasks.data ?? []) as Task[],
    chores: (chores.data ?? []) as Chore[],
    choreCompletions: (choreCompletions.data ?? []) as ChoreCompletion[],
    attachments: (attachments.data ?? []) as Attachment[],
    activityLog: (activityLog.data ?? []) as ActivityLog[],
  };
}

/**
 * Boots the app's data layer once at the root:
 * 1. Instant paint from the last IndexedDB snapshot (works fully offline).
 * 2. Fresh fetch from Supabase to reconcile (small dataset — refetch-all is
 *    simpler and just as fast as a delta query at this scale).
 * 3. A single realtime channel that keeps every table live from then on.
 * 4. Reconnect handling: flush queued offline writes, then refetch once.
 */
export function useRealtimeSync() {
  const hydrate = useAppStore((s) => s.hydrate);
  const applyRemote = useAppStore((s) => s.applyRemote);

  useEffect(() => {
    let cancelled = false;

    (async () => {
      const cached = await loadSnapshot<Snapshot>();
      if (cached && !cancelled) hydrate(cached);

      try {
        const fresh = await fetchAll();
        if (!cancelled) {
          hydrate(fresh);
          void saveSnapshot(fresh);
        }
      } catch {
        // Offline with no cache yet: the empty/cached state stands until reconnect.
      }
    })();

    const supabase = createClient();
    const channel = supabase.channel("kh:db");
    for (const table of TABLES) {
      channel.on(
        "postgres_changes" as never,
        { event: "*", schema: "public", table },
        (payload: { eventType: "INSERT" | "UPDATE" | "DELETE"; new: Record<string, unknown>; old: Record<string, unknown> }) => {
          applyRemote(table, payload.eventType, payload.new ?? null, payload.old ?? null);
        }
      );
    }
    channel.subscribe();

    const handleOnline = async () => {
      await flushMutationQueue();
      try {
        const fresh = await fetchAll();
        hydrate(fresh);
        void saveSnapshot(fresh);
      } catch {
        // best-effort
      }
    };
    window.addEventListener("online", handleOnline);

    // Keep the offline snapshot fresh so a later cold start (no network yet) has data.
    const unsubscribeSnapshot = useAppStore.subscribe((state) => {
      void saveSnapshot({
        members: Object.values(state.members),
        sections: Object.values(state.sections),
        tasks: Object.values(state.tasks),
        chores: Object.values(state.chores),
        choreCompletions: Object.values(state.choreCompletions),
        attachments: Object.values(state.attachments),
        activityLog: Object.values(state.activityLog),
      });
    });

    return () => {
      cancelled = true;
      window.removeEventListener("online", handleOnline);
      unsubscribeSnapshot();
      supabase.removeChannel(channel);
    };
  }, [hydrate, applyRemote]);
}

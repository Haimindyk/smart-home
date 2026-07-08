"use client";

import { useEffect } from "react";
import { REALTIME_SUBSCRIBE_STATES, type RealtimeChannel } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import { useAppStore } from "@/lib/store/app-store";
import { loadSnapshot, saveSnapshot } from "@/lib/offline/db";
import { flushMutationQueue } from "@/lib/offline/queue";
import type { Member, Section, Task, Chore, ChoreCompletion, Attachment, ActivityLog, FamilyEvent } from "@/types/domain";

/** Delay before rejoining the realtime channel after an error/timeout/close, to avoid retry storms. */
const REJOIN_DELAY_MS = 2000;

type Snapshot = {
  members: Member[];
  sections: Section[];
  tasks: Task[];
  chores: Chore[];
  choreCompletions: ChoreCompletion[];
  attachments: Attachment[];
  activityLog: ActivityLog[];
  familyEvents: FamilyEvent[];
};

const TABLES = [
  "members",
  "sections",
  "tasks",
  "chores",
  "chore_completions",
  "attachments",
  "activity_log",
  "family_events",
] as const;

async function fetchAll(): Promise<Snapshot> {
  const supabase = createClient();
  const [members, sections, tasks, chores, choreCompletions, attachments, activityLog, familyEvents] = await Promise.all([
    supabase.from("members").select("*"),
    supabase.from("sections").select("*").order("position"),
    supabase.from("tasks").select("*").order("position"),
    supabase.from("chores").select("*").order("position"),
    supabase.from("chore_completions").select("*"),
    supabase.from("attachments").select("*"),
    supabase.from("activity_log").select("*").order("seq", { ascending: false }).limit(200),
    supabase.from("family_events").select("*").order("event_date"),
  ]);
  return {
    members: (members.data ?? []) as Member[],
    sections: (sections.data ?? []) as Section[],
    tasks: (tasks.data ?? []) as Task[],
    chores: (chores.data ?? []) as Chore[],
    choreCompletions: (choreCompletions.data ?? []) as ChoreCompletion[],
    attachments: (attachments.data ?? []) as Attachment[],
    activityLog: (activityLog.data ?? []) as ActivityLog[],
    familyEvents: (familyEvents.data ?? []) as FamilyEvent[],
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
    let channel: RealtimeChannel | null = null;
    let rejoinTimer: ReturnType<typeof setTimeout> | null = null;

    const supabase = createClient();

    // Fetches everything fresh and reconciles the store — this is the one
    // resync path used on first boot, on reconnect (online), on channel
    // re-subscribe, and on tab foreground (visibilitychange).
    const resync = async () => {
      try {
        const fresh = await fetchAll();
        if (cancelled) return;
        hydrate(fresh);
        void saveSnapshot(fresh);
      } catch {
        // Offline / transient failure: cached or current state stands until next resync.
      }
    };

    const clearRejoinTimer = () => {
      if (rejoinTimer !== null) {
        clearTimeout(rejoinTimer);
        rejoinTimer = null;
      }
    };

    // Builds and subscribes the single "kh:db" channel. On drop
    // (error/timeout/close) it tears itself down and schedules a rejoin
    // after a short delay, so a backgrounded/slept device self-heals instead
    // of going stale until a manual reload.
    const connect = () => {
      const ch = supabase.channel("kh:db");
      for (const table of TABLES) {
        ch.on(
          "postgres_changes" as never,
          { event: "*", schema: "public", table },
          (payload: { eventType: "INSERT" | "UPDATE" | "DELETE"; new: Record<string, unknown>; old: Record<string, unknown> }) => {
            applyRemote(table, payload.eventType, payload.new ?? null, payload.old ?? null);
          }
        );
      }
      channel = ch;
      ch.subscribe((status) => {
        if (cancelled) return;
        if (status === REALTIME_SUBSCRIBE_STATES.SUBSCRIBED) {
          // Catches anything missed while (re)connecting.
          void resync();
        } else if (
          status === REALTIME_SUBSCRIBE_STATES.CHANNEL_ERROR ||
          status === REALTIME_SUBSCRIBE_STATES.TIMED_OUT ||
          status === REALTIME_SUBSCRIBE_STATES.CLOSED
        ) {
          if (rejoinTimer !== null) return; // a rejoin is already scheduled
          rejoinTimer = setTimeout(() => {
            rejoinTimer = null;
            if (cancelled) return;
            supabase.removeChannel(ch);
            if (channel === ch) channel = null;
            connect();
          }, REJOIN_DELAY_MS);
        }
      });
    };

    (async () => {
      const cached = await loadSnapshot<Snapshot>();
      if (cached && !cancelled) hydrate(cached);
      await resync();
    })();

    connect();

    const handleOnline = async () => {
      await flushMutationQueue();
      await resync();
    };
    window.addEventListener("online", handleOnline);

    const handleVisibilityChange = () => {
      if (document.visibilityState === "visible") void resync();
    };
    document.addEventListener("visibilitychange", handleVisibilityChange);

    // Keep the offline snapshot fresh so a later cold start (no network yet) has data.
    const unsubscribeSnapshot = useAppStore.subscribe((state) => {
      void saveSnapshot({
        members: Object.values(state.members),
        sections: Object.values(state.sections),
        tasks: Object.values(state.tasks),
        chores: Object.values(state.chores),
        choreCompletions: Object.values(state.choreCompletions),
        attachments: Object.values(state.attachments),
        // Cap what's persisted to the newest ~200 (matches the initial fetch limit)
        // so a cold start's IndexedDB payload stays bounded.
        activityLog: Object.values(state.activityLog)
          .sort((a, b) => b.seq - a.seq)
          .slice(0, 200),
        familyEvents: Object.values(state.familyEvents),
      });
    });

    return () => {
      cancelled = true;
      clearRejoinTimer();
      window.removeEventListener("online", handleOnline);
      document.removeEventListener("visibilitychange", handleVisibilityChange);
      unsubscribeSnapshot();
      if (channel) supabase.removeChannel(channel);
    };
  }, [hydrate, applyRemote]);
}

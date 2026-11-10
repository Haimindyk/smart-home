"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { healthFunction } from "@/lib/health/api";
import { useHealthStore } from "@/lib/health/store";
import { useHealthText } from "@/lib/health/i18n";
import { exerciseSchema } from "@/lib/health/model";
import { wellnessExercises } from "../../../supabase/functions/_shared/exercise-catalog";
import {
  parseChatAnswer,
  type ChatTurn,
} from "../../../supabase/functions/_shared/wellness-chat-core";
import { AiConsent, useWellnessAvailability } from "./ai-consent";
import { ExerciseDemo } from "./exercise-demo";
import { Panel, ErrorText, Disclosure } from "./shared";
type ChatState = {
  generation: string;
  version: number;
  used: number;
  limit: number;
  available: boolean;
  turns: ChatTurn[];
  resetAt: string;
};
async function request<T>(body: Record<string, unknown>): Promise<T> {
  const owner = useHealthStore.getState().owner;
  if (!owner) throw new Error("session_required");
  if (!navigator.onLine) throw new Error("online_required");
  const result = await healthFunction<T>("wellness-chat", body, owner);
  if (useHealthStore.getState().owner !== owner)
    throw new Error("session_mismatch");
  return result;
}
function ExerciseReference({ id }: { id: string }) {
  const h = useHealthText(),
    [open, setOpen] = useState(false),
    c = wellnessExercises.find((c) => c.id === id);
  if (!c) return null;
  return (
    <details className="mt-3" onToggle={(e) => setOpen(e.currentTarget.open)}>
      <summary className="cursor-pointer text-sm">
        {h("הדגמה ודגשים לתרגיל", "Exercise demonstration and cues")} · {c.he}
      </summary>
      {open && (
        <ExerciseDemo
          exercise={exerciseSchema.parse({
            id: crypto.randomUUID(),
            catalogId: c.id,
            demoId: c.demoId,
            name: c.he,
            loadUnknown: true,
          })}
        />
      )}
    </details>
  );
}
export function CoachChat({
  onNavigate,
}: {
  onNavigate?: (tab: "nutrition" | "workouts") => void;
}) {
  const h = useHealthText(),
    availability = useWellnessAvailability(),
    owner = useHealthStore((s) => s.owner);
  const [state, setState] = useState<ChatState | null>(null),
    [text, setText] = useState(""),
    [includeDiary, setIncludeDiary] = useState(false),
    [busy, setBusy] = useState(false),
    [loading, setLoading] = useState(true),
    [error, setError] = useState<string | null>(null);
  const retry = useRef<{
      id: string;
      text: string;
      includeDiary: boolean;
      generation: string;
      version: number;
    } | null>(null),
    last = useRef<HTMLDivElement>(null);
  const load = useCallback(async () => {
    const current = await request<ChatState>({ action: "state" });
    for (const turn of current.turns)
      turn.answer = parseChatAnswer(turn.answer);
    return current;
  }, []);
  useEffect(() => {
    let cancelled = false;
    void load()
      .then((s) => {
        if (!cancelled) setState(s);
      })
      .catch((e) => {
        if (!cancelled) setError(e instanceof Error ? e.message : "failed");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [owner, load]);
  async function refresh() {
    setLoading(true);
    setError(null);
    try {
      setState(await load());
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    } finally {
      setLoading(false);
    }
  }
  async function send() {
    if (!state || busy || !text.trim()) return;
    setBusy(true);
    setError(null);
    const message = text.trim();
    try {
      if (useHealthStore.getState().pending) throw new Error("sync_required");
      const previous = retry.current;
      const job =
        previous &&
        previous.text === message &&
        previous.includeDiary === includeDiary &&
        previous.generation === state.generation
          ? previous
          : {
              id: crypto.randomUUID(),
              text: message,
              includeDiary,
              generation: state.generation,
              version: state.version,
            };
      retry.current = job;
      const result = await request<{
        id: string;
        answer: unknown;
        version: number;
        generation: string;
      }>({
        action: "send",
        requestId: job.id,
        message: job.text,
        includeDiary: job.includeDiary,
        generation: job.generation,
        version: job.version,
      });
      const answer = parseChatAnswer(result.answer);
      setState((s) =>
        s
          ? {
              ...s,
              version: result.version,
              generation: result.generation,
              used: s.used + 1,
              turns: [
                ...s.turns.filter((t) => t.id !== result.id),
                {
                  id: result.id,
                  user_text: message,
                  answer,
                  shared_diary: includeDiary,
                  created_at: new Date().toISOString(),
                },
              ].slice(-40),
            }
          : s,
      );
      retry.current = null;
      setText("");
      try {
        setState(await load());
      } catch {
        /* Retain the confirmed reply if refresh is offline. */
      }
      requestAnimationFrame(() =>
        last.current?.scrollIntoView({ behavior: "smooth", block: "nearest" }),
      );
    } catch (e) {
      const code = e instanceof Error ? e.message : "failed";
      setError(code === "version_conflict" ? "chat_changed" : code);
      if (code === "version_conflict" || code === "request_conflict")
        retry.current = null;
      if (useHealthStore.getState().owner === owner) {
        try {
          setState(await load());
        } catch {
          /* Keep the draft and explicit refresh action. */
        }
      }
    } finally {
      setBusy(false);
    }
  }
  async function clear() {
    if (
      !window.confirm(
        h(
          "למחוק את היסטוריית השיחה? המכסה היומית לא מתאפסת.",
          "Delete the conversation history? Your daily allowance will not reset.",
        ),
      )
    )
      return;
    setBusy(true);
    setError(null);
    try {
      await request({ action: "clear" });
      retry.current = null;
      setState(await load());
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    } finally {
      setBusy(false);
    }
  }
  const canSend =
    availability.ready &&
    state?.available &&
    !busy &&
    !loading &&
    state.used < state.limit;
  return (
    <Panel
      title={h("השיחה שלך", "Your conversation")}
      className="health-coach"
      action={
        <Button
          variant="ghost"
          disabled={busy || !state?.turns.length}
          onClick={() => void clear()}
        >
          {h("מחיקת שיחה", "Clear chat")}
        </Button>
      }
    >
      <div className="grid min-w-0 gap-4">
        <p className="text-sm text-muted-foreground">{h("אוכל, אימונים וטכניקה — מה תרצו לדעת?", "Food, training or technique — what’s on your mind?")}</p>
        <AiConsent />
        <ErrorText error={error} />
        <div className="flex flex-wrap items-center justify-between gap-2">
          <span className="health-status">{state ? h(`${state.used}/${state.limit} הודעות היום`,`${state.used}/${state.limit} messages today`) : h("טוען שיחה…","Loading conversation…")}</span>
          <Button size="sm" variant="ghost" disabled={busy || loading} onClick={()=>void refresh()}>{h("רענון שיחה", "Refresh chat")}</Button>
        </div>
        <div
          role="log"
          aria-label={h("השיחה עם המאמן", "Conversation with your coach")}
          aria-live="polite"
          aria-relevant="additions"
          className="health-coach-log grid min-w-0 gap-4"
        >
          {loading && !state && (
            <p role="status">{h("טוען שיחה…", "Loading conversation…")}</p>
          )}
          {state && !state.turns.length && (
            <div className="health-chat-empty"><strong>{h("על מה נדבר?", "What’s on your mind?")}</strong><div className="health-chat-prompts">{[h("איך לחלק חלבון ביום?","How can I spread protein through the day?"),h("מה ההבדל בין Full Body ל־AB?","Full Body or AB?"),h("איך לבצע סקוואט?","How do I squat?")].map(prompt=><button type="button" key={prompt} onClick={()=>setText(prompt)}>{prompt}</button>)}</div></div>
          )}
          {state?.turns.map((turn) => (
            <section key={turn.id} className="grid min-w-0 gap-2">
              <div className="ms-6 rounded-2xl bg-primary/10 p-4">
                <p className="mb-1 text-xs font-semibold">{h("אני", "You")}</p>
                <p className="whitespace-pre-wrap break-words text-sm leading-7 [overflow-wrap:anywhere]">
                  {turn.user_text}
                </p>
                {turn.shared_diary && (
                  <small className="text-muted-foreground">
                    {h("צורף סיכום יומן", "Diary summary shared")}
                  </small>
                )}
              </div>
              <div className="me-3 rounded-2xl border p-4">
                <p className="mb-1 text-xs font-semibold">
                  {h("המאמן · AI", "Coach · AI")}
                </p>
                <p className="whitespace-pre-wrap break-words text-sm leading-7 [overflow-wrap:anywhere]">
                  {turn.answer.reply}
                </p>
                {turn.answer.exerciseIds.map((id) => (
                  <ExerciseReference key={id} id={id} />
                ))}
                <div className="mt-3 flex flex-wrap gap-2">
                  {turn.answer.followUps.map((question) => (
                    <Button
                      key={question}
                      size="sm"
                      variant="outline"
                      disabled={busy}
                      className="h-auto max-w-full whitespace-normal text-start"
                      onClick={() => setText(question)}
                    >
                      {question}
                    </Button>
                  ))}
                </div>
              </div>
            </section>
          ))}
          {busy && (
            <p role="status" className="text-sm">
              {h("המאמן חושב…", "Your coach is thinking…")}
            </p>
          )}
          <div ref={last} />
        </div>
        <form
          className="health-coach-composer grid min-w-0 gap-3"
          onSubmit={(e) => {
            e.preventDefault();
            void send();
          }}
        >
          <label className="grid gap-2 text-sm">
            <span>{h("מה תרצו לשאול?", "What would you like to ask?")}</span>
            <textarea
              maxLength={2000}
              rows={2}
              value={text}
              onChange={(e) => setText(e.target.value)}
              className="min-w-0 resize-y rounded-xl border bg-background p-3"
              placeholder={h(
                "למשל: איך לעשות סקוואט בצורה נכונה?",
                "For example: how do I perform a squat correctly?",
              )}
            />
          </label>
          <label className="flex items-start gap-2 text-xs leading-6">
            <input
              type="checkbox"
              className="mt-1.5"
              checked={includeDiary}
              disabled={busy}
              onChange={(e) => setIncludeDiary(e.target.checked)}
            />
            {h(
              "לצרף סיכום יומן: ערכי היום, היעד ואימונים אחרונים",
              "Include diary summary: today’s nutrients, target and recent workouts",
            )}
          </label>
          <Button type="submit" disabled={!canSend || !text.trim()}>
            {h("שליחה למאמן", "Send to coach")}
          </Button>
        </form>
        {onNavigate && (
          <div className="flex flex-wrap gap-2">
            <Button variant="outline" onClick={() => onNavigate("nutrition")}>
              {h("יומן תזונה", "Nutrition diary")}
            </Button>
            <Button variant="outline" onClick={() => onNavigate("workouts")}>
              {h("תוכניות אימון", "Workout plans")}
            </Button>
          </div>
        )}
        <Disclosure className="health-help" title={h("פרטיות, מכסה ומה נשמר", "Privacy, allowance and saved changes")}><p>{h("מידע כללי ב־AI, לא תחליף לתזונאי או לאיש מקצוע רפואי. השיחה פרטית ונשמרת עד 30 יום; רק ההודעות האחרונות נשלחות. סיכום יומן נשלח רק בסימון שלך, ללא תמונות, שם או הערות אישיות. המכסה כפופה גם לתקציב המשותף ומתאפסת בחצות UTC, ללא מעבר לתשלום. הצ׳אט לא משנה יומן או תוכנית; שינוי נשמר רק במסך המתאים לאחר אישור.", "General AI information, not a substitute for a licensed dietitian or clinician. Private history is retained for up to 30 days; only recent messages are sent. Diary summaries are opt-in and exclude photos, name and personal notes. A shared allowance also applies, resetting at midnight UTC without paid fallback. Chat does not edit your diary or plan; approve changes in the appropriate screen.")}</p></Disclosure>
      </div>
    </Panel>
  );
}

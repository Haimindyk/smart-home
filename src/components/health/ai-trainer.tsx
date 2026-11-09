"use client";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { useHealthStore } from "@/lib/health/store";
import {
  wellnessRequest,
  type CoachProposal,
  type TrainingPreferences,
} from "@/lib/health/wellness-api";
import { payloadSchemas } from "@/lib/health/model";
import { useHealthText } from "@/lib/health/i18n";
import { wellnessExercises } from "../../../supabase/functions/_shared/exercise-catalog";
import type { PlanData } from "../../../supabase/functions/_shared/wellness-core";
import { AiConsent, useWellnessAvailability } from "./ai-consent";
import { Panel, Field, SelectField, ErrorText, Disclosure, ChoiceTabs } from "./shared";

import { HealthSheet } from "./health-sheet";

const muscleLabels: Record<string, [string, string]> = {
  legs: ["רגליים", "Legs"],
  hamstrings: ["ירך אחורית", "Hamstrings"],
  glutes: ["ישבן", "Glutes"],
  chest: ["חזה", "Chest"],
  back: ["גב", "Back"],
  shoulders: ["כתפיים", "Shoulders"],
  biceps: ["יד קדמית", "Biceps"],
  triceps: ["יד אחורית", "Triceps"],
  calves: ["שוקיים", "Calves"],
  core: ["ליבה", "Core"],
};
const equipmentLabels: Record<string, [string, string]> = {
  bodyweight: ["משקל גוף", "Bodyweight"],
  dumbbell: ["דאמבלים", "Dumbbells"],
  barbell: ["מוט", "Barbell"],
  machine: ["מכונות", "Machines"],
  cable: ["כבלים", "Cable"],
  pullup: ["מתקן מתח", "Pull-up bar"],
};
const defaults: TrainingPreferences = {
  goal: "muscle",
  experience: "beginner",
  days: [0, 2, 4],
  minutes: 45,
  split: "auto",
  focus: [],
  equipment: ["bodyweight", "dumbbell", "machine", "cable"],
  avoid: [],
  notes: "",
};
type Proposal = CoachProposal & { requestId: string };
type Version = {
  id: string;
  plan_id: string;
  previous_data: PlanData | null;
  applied_data: PlanData;
  created_at: string;
};
export function AiTrainer({ date }: { date: string }) {
  const h = useHealthText(),
    availability = useWellnessAvailability(),
    data = useHealthStore((s) => s.data),
    profile = data.health_profiles[0];
  const [preferences, setPreferences] = useState<TrainingPreferences>(
    () => profile?.data.trainingPreferences ?? defaults,
  );
  const [mode, setMode] = useState<"program" | "adjust">("program"),
    [planId, setPlanId] = useState(""),
    [question, setQuestion] = useState("");
  const [proposal, setProposal] = useState<Proposal | null>(null),
    [busy, setBusy] = useState(false),
    [error, setError] = useState<string | null>(null),
    [notice, setNotice] = useState("");
  const [versions, setVersions] = useState<Version[] | null>(null),
    [open, setOpen] = useState(false);
  function toggle(
    key: "days" | "focus" | "equipment" | "avoid",
    value: string | number,
  ) {
    setPreferences((p) => {
      const list = p[key] as (string | number)[];
      if (list.includes(value))
        return { ...p, [key]: list.filter((x) => x !== value) };
      if (
        (key === "focus" && list.length === 2) ||
        (key === "days" && list.length === 6)
      )
        return p;
      return { ...p, [key]: [...list, value] };
    });
  }
  async function generate() {
    setBusy(true);
    setError(null);
    setNotice("");
    setProposal(null);
    const owner = useHealthStore.getState().owner;
    try {
      if (useHealthStore.getState().pending) throw new Error("sync_required");
      const current = useHealthStore.getState().data.health_profiles[0];
      if (!current) throw new Error("adult_profile_required");
      // Save the settings through the existing optimistic/versioned private profile path.
      await useHealthStore
        .getState()
        .save(
          "health_profiles",
          { ...current.data, trainingPreferences: preferences },
          current,
        );
      if (useHealthStore.getState().pending) throw new Error("sync_required");
      if (useHealthStore.getState().owner !== owner)
        throw new Error("session_mismatch");
      const response = await wellnessRequest<Proposal>({
        action: mode,
        requestId: crypto.randomUUID(),
        preferences,
        date,
        planId,
        description:
          question ||
          h(
            "סקור/י את התוכנית לפי הביצועים והמשוב שלי.",
            "Review my plan using my performance and feedback.",
          ),
      });
      for (const change of response.changes)
        payloadSchemas.workout_plans.parse(change.data);
      setProposal(response);
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    } finally {
      setBusy(false);
    }
  }
  async function apply() {
    if (!proposal) return;
    setBusy(true);
    setError(null);
    try {
      if (useHealthStore.getState().pending) throw new Error("sync_required");
      await wellnessRequest({ action: "apply", requestId: proposal.requestId });
      await useHealthStore.getState().refresh();
      setProposal(null);
      setVersions(null);
      setNotice(
        h(
          "השינוי שאישרת נשמר. הגרסה הקודמת זמינה בהיסטוריה.",
          "Your approved change was saved. The previous version is in history.",
        ),
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    } finally {
      setBusy(false);
    }
  }
  async function history() {
    setBusy(true);
    setError(null);
    try {
      const response = await wellnessRequest<{ versions: Version[] }>({
        action: "history",
      });
      setVersions(response.versions);
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    } finally {
      setBusy(false);
    }
  }
  return (
    <Panel
      title={h("תוכנית שמתאימה לך", "A plan for you")}
      action={
        <Button
          variant="outline"
          onClick={() => setOpen((x) => !x)}
          aria-expanded={open}
        >
          {open
            ? h("סגירה", "Close")
            : h("תוכנית עם AI", "Plan with AI")}
        </Button>
      }
    >
      <p className="text-sm text-muted-foreground">
        {h(
          "תוכנית לפי המטרה והציוד שלך.",
          "A plan that fits your goal and equipment.",
        )}
      </p>
      {open && (
        <HealthSheet title={h("תוכנית עם AI", "Plan with AI")} onClose={()=>setOpen(false)}>
        <div className="grid gap-4">
          <AiConsent />
          <ErrorText error={error} />
          {notice && (
            <p role="status" className="rounded-xl bg-primary/10 p-3">
              {notice}
            </p>
          )}
          <ChoiceTabs label={h("סוג בקשה", "Request type")} value={mode} onChange={next=>{setMode(next);setProposal(null)}} options={[{value:"program",label:h("תוכנית חדשה","New program")},{value:"adjust",label:h("שיפור תוכנית","Improve a plan")}]} />
          <div className="grid gap-3 sm:grid-cols-2">
            <SelectField
              label={h("המטרה שלי", "My goal")}
              value={preferences.goal}
              onChange={(e) =>
                setPreferences((p) => ({
                  ...p,
                  goal: e.target.value as TrainingPreferences["goal"],
                }))
              }
            >
              <option value="muscle">{h("בניית שריר", "Build muscle")}</option>
              <option value="strength">{h("חיזוק וכוח", "Strength")}</option>
              <option value="fitness">
                {h("כושר כללי", "General fitness")}
              </option>
            </SelectField>
            <SelectField
              label={h("ניסיון באימון", "Training experience")}
              value={preferences.experience}
              onChange={(e) =>
                setPreferences((p) => ({
                  ...p,
                  experience: e.target
                    .value as TrainingPreferences["experience"],
                }))
              }
            >
              <option value="beginner">{h("מתחיל/ה", "Beginner")}</option>
              <option value="intermediate">{h("מנוסה", "Intermediate")}</option>
              <option value="advanced">{h("מתקדם/ת", "Advanced")}</option>
            </SelectField>
            <SelectField
              label={h("חלוקת האימונים", "Training split")}
              value={preferences.split}
              onChange={(e) =>
                setPreferences((p) => ({
                  ...p,
                  split: e.target.value as TrainingPreferences["split"],
                }))
              }
            >
              <option value="auto">
                {h("התאם לי חלוקה", "Choose for me")}
              </option>
              <option value="full_body">{h("Full Body · כל הגוף", "Full Body · whole body")}</option>
              <option value="ab">{h("AB · שני אימונים", "AB · two sessions")}</option>
              <option value="abc">{h("ABC · שלושה אימונים", "ABC · three sessions")}</option>
              <option value="custom">
                {h(
                  "חלוקה אישית לפי ימי האימון",
                  "Custom split for my training days",
                )}
              </option>
            </SelectField>
            <Field
              type="number"
              min={20}
              max={120}
              step={5}
              label={h("דקות לאימון", "Minutes per workout")}
              value={preferences.minutes}
              onChange={(e) =>
                setPreferences((p) => ({
                  ...p,
                  minutes: Number(e.target.value),
                }))
              }
            />
          </div>
          <fieldset>
            <legend className="mb-2 text-sm font-medium">
              {h(
                "ימי האימון שלי · עד 6 בשבוע",
                "My training days · up to 6 a week",
              )}
            </legend>
            <div className="flex flex-wrap gap-2">
              {[0, 1, 2, 3, 4, 5, 6].map((day) => (
                <button
                  type="button"
                  key={day}
                  aria-pressed={preferences.days.includes(day)}
                  onClick={() => toggle("days", day)}
                  className={`rounded-full border px-3 py-2 text-sm ${preferences.days.includes(day) ? "bg-primary text-primary-foreground" : ""}`}
                >
                  {h(
                    ["א׳", "ב׳", "ג׳", "ד׳", "ה׳", "ו׳", "ש׳"][day],
                    ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][day],
                  )}
                </button>
              ))}
            </div>
          </fieldset>
          <fieldset>
            <legend className="mb-2 text-sm font-medium">
              {h("הציוד הזמין", "Available equipment")}
            </legend>
            <div className="flex flex-wrap gap-3">
              {Object.entries(equipmentLabels).map(([key, label]) => (
                <label key={key} className="health-option-chip">
                  <input
                    type="checkbox"
                    checked={preferences.equipment.includes(key)}
                    onChange={() => toggle("equipment", key)}
                  />
                  {h(...label)}
                </label>
              ))}
            </div>
          </fieldset>
          <Disclosure title={h("דגשים והעדפות", "Focus and preferences")}>
          <fieldset>
            <legend className="mb-2 text-sm font-medium">
              {h(
                "שרירים בדגש · עד שניים",
                "Muscle focus · up to two",
              )}
            </legend>
            <div className="flex flex-wrap gap-2">
              {Object.entries(muscleLabels).map(([key, label]) => (
                <button
                  type="button"
                  key={key}
                  aria-pressed={preferences.focus.includes(key)}
                  onClick={() => toggle("focus", key)}
                  className={`rounded-full border px-3 py-1.5 text-sm ${preferences.focus.includes(key) ? "bg-primary text-primary-foreground" : ""}`}
                >
                  {h(...label)}
                </button>
              ))}
            </div>
          </fieldset>
          <details>
            <summary className="cursor-pointer text-sm">
              {h("תרגילים שלא רוצים לבצע", "Exercises to avoid")}
            </summary>
            <div className="mt-3 grid max-h-48 grid-cols-1 gap-2 overflow-y-auto sm:grid-cols-2">
              {wellnessExercises.map((e) => (
                <label key={e.id} className="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    checked={preferences.avoid.includes(e.id)}
                    onChange={() => toggle("avoid", e.id)}
                  />
                  {h(e.he, e.en)}
                </label>
              ))}
            </div>
          </details>
          </Disclosure>
          {mode === "program" ? (
            <Disclosure className="health-help" title={h("משהו נוסף שכדאי לדעת?", "Anything else to consider?")}>
            <Field
              label={h(
                "העדפות נוספות (בלי מידע רפואי מזהה)",
                "Other preferences (no identifying medical information)",
              )}
              maxLength={1000}
              value={preferences.notes}
              onChange={(e) =>
                setPreferences((p) => ({ ...p, notes: e.target.value }))
              }
            />
            </Disclosure>
          ) : (
            <>
              <SelectField
                label={h("איזו תוכנית לשפר?", "Which plan should we improve?")}
                value={planId}
                onChange={(e) => setPlanId(e.target.value)}
              >
                <option value="">{h("בחירת תוכנית", "Choose a plan")}</option>
                {data.workout_plans
                  .filter((p) => !p.data.archived)
                  .map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.data.name}
                    </option>
                  ))}
              </SelectField>
              <Field
                maxLength={1000}
                label={h(
                  "מה לשנות או לבדוק?",
                  "What should we change or review?",
                )}
                placeholder={h(
                  "למשל: התאמת התוכנית הקבועה לחצי שעה ודגש על גב",
                  "For example: adapt my regular plan to 30 minutes with more back work",
                )}
                value={question}
                onChange={(e) => setQuestion(e.target.value)}
              />
            </>
          )}
          <Disclosure className="health-help" title={h("איך התוכנית נבנית ונשמרת?", "How plans work")}>
          <p className="text-xs text-muted-foreground">
            {h(
              "חלוקת AB או ABC ממשיכה במחזור גם בין שבועות. תוכנית חדשה תתווסף לצד הקיימות. משקל התחלתי לא ינוחש. שיפור שאושר משנה את התוכנית הקבועה.",
              "AB/ABC rotates across weeks. A new program is added alongside existing plans. Starting loads are never guessed. Approved adjustments update the saved plan.",
            )}
          </p>
          </Disclosure>
          <Button className="health-primary-action"
            disabled={
              !availability.ready ||
              busy ||
              !preferences.days.length ||
              !preferences.equipment.length ||
              (mode === "adjust" && !planId)
            }
            onClick={() => void generate()}
          >
            {busy
              ? h("מכין הצעה…", "Preparing a proposal…")
              : mode === "program" ? h("יצירת תוכנית", "Create program") : h("הצעת שיפור", "Suggest changes")}
          </Button>
          {proposal && (
            <section
              className="rounded-2xl border bg-muted/20 p-4"
              aria-label={h("הצעה לאישור", "Proposal to approve")}
            >
              <p className="text-sm font-semibold">{h("התוכנית מוכנה לבדיקה", "Your plan is ready to review")}</p>
              <Disclosure className="health-help" title={h("למה התוכנית מתאימה לי?", "Why this plan?")}><p className="whitespace-pre-wrap">{proposal.message}</p>{proposal.reasons.map((reason,index)=><p key={index}>{reason}</p>)}</Disclosure>
              {proposal.changes.map((change) => {
                const previous = data.workout_plans.find(
                  (p) => p.id === change.id,
                );
                return (
                  <div
                    key={change.id}
                    className="mt-4 rounded-xl border bg-background p-3"
                  >
                    <h3 className="font-semibold">{change.data.name}</h3>
                    {previous && (
                      <p className="mt-1 text-xs text-muted-foreground">
                        {h("לפני:", "Before:")}{" "}
                        {previous.data.exercises
                          .map(
                            (e) =>
                              `${e.name}: ${e.sets}×${e.reps}, ${e.weight}kg`,
                          )
                          .join(" · ")}
                      </p>
                    )}
                    <ul className="mt-3 grid gap-2 text-sm">
                      {change.data.exercises.map((e) => (
                        <li key={e.id}>
                          {e.name} · {e.sets} ×{" "}
                          {e.holdSeconds ? `${e.holdSeconds}s` : e.reps} ·{" "}
                          {h("מנוחה", "rest")} {e.rest}s ·{" "}
                          {e.loadUnknown
                            ? h("משקל ייקבע באימון", "set load during workout")
                            : `${e.weight}kg`}
                        </li>
                      ))}
                    </ul>
                    <p className="mt-2 text-sm text-muted-foreground">
                      {change.data.notes}
                    </p>
                  </div>
                );
              })}
              <div className="mt-4 flex flex-wrap gap-2">
                {!!proposal.changes.length && (
                  <Button disabled={busy} onClick={() => void apply()}>
                    {h("אישור ושמירת השינוי", "Approve and save changes")}
                  </Button>
                )}
                <Button
                  disabled={busy}
                  variant="outline"
                  onClick={async () => {
                    setError(null);
                    try {
                      await wellnessRequest({
                        action: "reject",
                        requestId: proposal.requestId,
                      });
                      setProposal(null);
                    } catch (e) {
                      setError(e instanceof Error ? e.message : "failed");
                    }
                  }}
                >
                  {h("לא עכשיו", "Not now")}
                </Button>
              </div>
            </section>
          )}
          <Button
            variant="ghost"
            disabled={!availability.manageReady || busy}
            onClick={() => void history()}
          >
            {h("גרסאות ושחזור תוכניות", "Plan versions and restore")}
          </Button>
          {versions && (
            <div className="grid gap-2">
              {!versions.length && (
                <p className="text-sm text-muted-foreground">
                  {h("עדיין אין שינויים שאושרו.", "No approved changes yet.")}
                </p>
              )}
              {versions.map((v) => (
                <div
                  key={v.id}
                  className="flex items-center justify-between gap-2 rounded-xl border p-3 text-sm"
                >
                  <span>
                    {v.applied_data.name} ·{" "}
                    {new Date(v.created_at).toLocaleDateString()}
                  </span>
                  <Button
                    variant="outline"
                    disabled={busy}
                    onClick={async () => {
                      setBusy(true);
                      setError(null);
                      try {
                        setProposal(
                          await wellnessRequest<Proposal>({
                            action: "restore",
                            versionId: v.id,
                            requestId: crypto.randomUUID(),
                          }),
                        );
                      } catch (e) {
                        setError(e instanceof Error ? e.message : "failed");
                      } finally {
                        setBusy(false);
                      }
                    }}
                  >
                    {v.previous_data
                      ? h("הצגת שחזור לאישור", "Review restoration")
                      : h("הצגת העברה לארכיון", "Review archiving")}
                  </Button>
                </div>
              ))}
            </div>
          )}
        </div>
        </HealthSheet>
      )}
    </Panel>
  );
}

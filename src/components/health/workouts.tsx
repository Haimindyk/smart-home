"use client";
import { useEffect, useState } from "react";
import { HealthSheet } from "./health-sheet";
import { AiTrainer } from "./ai-trainer";
import { isPlanScheduled } from "../../../supabase/functions/_shared/wellness-core";
import { Button } from "@/components/ui/button";
import { useHealthStore } from "@/lib/health/store";
import demos from "@/lib/health/exercise-demos.json";
import { ExerciseDemo, ExerciseThumbnail, resolveExerciseDemo } from "./exercise-demo";
import { exerciseCatalog } from "@/lib/health/exercises";
import { workoutVolume } from "@/lib/health/calculations";
import {
  exerciseSchema,
  type Exercise,
  type HealthRow,
  type Payload,
  type PerformedExercise,
} from "@/lib/health/model";
import { useHealthText } from "@/lib/health/i18n";
import { Panel, Field, SelectField, Empty, ErrorText, round } from "./shared";
const daysHe = ["א׳", "ב׳", "ג׳", "ד׳", "ה׳", "ו׳", "ש׳"],
  daysEn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
function planDayNumber(name:string) {
  const match=name.match(/(?:יום|day)\s*(\d+)/i);
  return match ? Number(match[1]) : Number.POSITIVE_INFINITY;
}
function planTitle(name:string) {
  return name.replace(/^\s*(?:יום|day)\s*\d+\s*[–—-]?\s*/i,"").trim()||name;
}
export function Workouts({
  date,
  onFocusChange,
}: {
  date: string;
  onFocusChange?: (focused:boolean)=>void;
}) {
  const h = useHealthText();
  const data = useHealthStore((s) => s.data),
    save = useHealthStore((s) => s.save);
  const [editing, setEditing] = useState<HealthRow<"workout_plans"> | null>(
      null,
    ),
    [planEditor, setPlanEditor] = useState(false),
    [session, setSession] = useState<HealthRow<"workout_sessions"> | null>(
      null,
    ),
    [selectedPlanId,setSelectedPlanId]=useState<string|null>(null),
    [editingExerciseId,setEditingExerciseId]=useState<string|null>(null),
    [error, setError] = useState<string | null>(null);
  const focused=!!session||planEditor||!!selectedPlanId;
  useEffect(()=>{onFocusChange?.(focused);if(focused)window.scrollTo(0,0);return()=>onFocusChange?.(false)},[focused,onFocusChange]);
  const plans = data.workout_plans.filter((p) => !p.data.archived).sort((a,b)=>planDayNumber(a.data.name)-planDayNumber(b.data.name)||a.data.name.localeCompare(b.data.name,undefined,{numeric:true}));
  const selectedPlan=plans.find(p=>p.id===selectedPlanId)??null;
  const sessions = data.workout_sessions.filter((s) => s.data.date === date && s.data.status!=="cancelled");
  async function start(plan: HealthRow<"workout_plans">, quick = false) {
    try {
      const now = new Date().toISOString();
      const exercises: PerformedExercise[] = quick
        ? []
        : plan.data.exercises.map((e) => ({
            ...e,
            skipped: false,
            performed: Array.from({ length: e.sets }, () => ({
              id: crypto.randomUUID(),
              reps: e.reps,
              weight: e.weight,
              done: false,
              seconds: e.holdSeconds,
              duration: e.duration,
              distance: e.distance,
            })),
          }));
      const row = await save("workout_sessions", {
        date,
        planId: plan.id,
        programNotes: plan.data.notes,
        name: plan.data.name,
        status: quick ? "completed" : "active",
        quick,
        startedAt: now,
        endedAt: quick ? now : null,
        notes: "",
        exercises,
      });
      if (!quick) setSession(row);
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    }
  }
  if(session) return <SessionEditor key={session.id} row={session} onClose={()=>setSession(null)}/>;
  if(planEditor) return <HealthSheet title={editing ? h("עריכת תוכנית", "Edit plan") : h("תוכנית חדשה", "New plan")} onClose={()=>setPlanEditor(false)}><PlanEditor key={editing?.id||editing?.data.name||"new"} existing={editing} initialExerciseId={editingExerciseId} onClose={()=>setPlanEditor(false)}/></HealthSheet>;
  if(selectedPlan) return <PlanDayView plan={selectedPlan} dayNumber={planDayNumber(selectedPlan.data.name)} onClose={()=>setSelectedPlanId(null)} onStart={()=>void start(selectedPlan)} onEdit={exerciseId=>{setEditing(selectedPlan);setEditingExerciseId(exerciseId??null);setPlanEditor(true)}}/>;
  return (
    <div className="grid gap-5">
      <ErrorText error={error} />
      <AiTrainer date={date}/>
      <Panel
        title={h("התכניות שלי", "My plans")}
        action={
          <Button
            onClick={() => {
              setEditing(null);
              setEditingExerciseId(null);
              setPlanEditor(true);
            }}
          >
            {h("תכנית חדשה", "New plan")}
          </Button>
        }
      >
        {plans.length === 0 ? (
          <Empty>
            {h(
              "בנו תכנית ראשונה כדי להתחיל",
              "Create your first plan to get started",
            )}
          </Empty>
        ) : (
          <div className="workout-plan-grid">
            {plans.map((p) => (
              <article key={p.id} className="workout-plan-tile">
                <button className="workout-day-open" onClick={()=>setSelectedPlanId(p.id)} aria-label={`${h("פתיחת", "Open")} ${p.data.name}`}>
                <ExerciseThumbnail exercise={p.data.exercises[0]}/>
                <span className="workout-day-copy">
                  <strong>{Number.isFinite(planDayNumber(p.data.name))?h(`יום ${planDayNumber(p.data.name)}`,`Day ${planDayNumber(p.data.name)}`):p.data.name}</strong>
                  <span>{planTitle(p.data.name)}</span>
                </span>
                  {isPlanScheduled(p.data,date) && (
                    <span className="rounded-full bg-primary/10 px-2 py-1 text-xs">
                      {h("בתכנון היום", "Scheduled today")}
                    </span>
                  )}
                </button>
                <p className="mt-1 text-sm text-muted-foreground">
                  {p.data.exercises.length} {h("תרגילים", "exercises")} ·{" "}
                  {p.data.days.map((d) => h(daysHe[d], daysEn[d])).join(" · ")}
                </p>
                <div className="mt-3 flex flex-wrap gap-2">
                  <Button size="sm" onClick={() => void start(p)}>
                    {h("התחלת אימון", "Start workout")}
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => {
                      setEditing(p);
                      setEditingExerciseId(null);
                      setPlanEditor(true);
                    }}
                  >
                    {h("עריכת תכנית", "Edit plan")}
                  </Button>
                  <details className="workout-tile-more"><summary>{h("עוד", "More")}</summary>
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() => void start(p, true)}
                  >
                    {h("בוצע בתאריך", "Mark done on date")}
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => {
                      setEditing({
                        ...p,
                        id: "",
                        version: 0,
                        data: {
                          ...p.data,
                          name: `${p.data.name} (${h("עותק", "copy")})`,
                        },
                      });
                      setPlanEditor(true);
                    }}
                  >
                    {h("שכפול", "Duplicate")}
                  </Button>
                  </details>
                </div>
              </article>
            ))}
          </div>
        )}
        {data.workout_plans.some((p) => p.data.archived) && (
          <details className="mt-4 text-sm">
            <summary>{h("ארכיון תכניות", "Archived plans")}</summary>
            {data.workout_plans
              .filter((p) => p.data.archived)
              .map((p) => (
                <div
                  className="mt-2 flex items-center justify-between"
                  key={p.id}
                >
                  <span>{p.data.name}</span>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() =>
                      void save(
                        "workout_plans",
                        { ...p.data, archived: false },
                        p,
                      ).catch(() => setError("failed"))
                    }
                  >
                    {h("שחזור", "Restore")}
                  </Button>
                </div>
              ))}
          </details>
        )}
      </Panel>
      <Panel title={h("אימונים בתאריך שנבחר", "Workouts on selected date")}>
        {sessions.length === 0 ? (
          <Empty>
            {h("אין אימון רשום בתאריך הזה", "No workouts logged on this date")}
          </Empty>
        ) : (
          sessions.map((s) => (
            <article key={s.id} className="mb-3 rounded-xl border p-3">
              <div className="flex items-center justify-between gap-2">
                <div>
                  <h3 className="font-semibold">{s.data.name}</h3>
                  <p className="mt-1 text-sm text-muted-foreground">
                    {
                      {
                        active: h("פעיל", "Active"),
                        partial: h("חלקי", "Partial"),
                        completed: h("הושלם", "Completed"),
                        cancelled: h("בוטל", "Cancelled"),
                      }[s.data.status]
                    }{" "}
                    ·{" "}
                    {s.data.quick
                      ? h("תיעוד מהיר ללא סטים", "Quick log without sets")
                      : `${round(workoutVolume(s.data.exercises))} kg · ${h("נפח", "volume")}`}
                  </p>
                </div>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setSession(s)}
                >
                  {h("פתיחה", "Open")}
                </Button>
              </div>
            </article>
          ))
        )}
      </Panel>
    </div>
  );
}
function PlanDayView({plan,dayNumber,onClose,onStart,onEdit}:{
  plan:HealthRow<"workout_plans">;
  dayNumber:number;
  onClose:()=>void;
  onStart:()=>void;
  onEdit:(exerciseId?:string)=>void;
}) {
  const h=useHealthText();
  const dayLabel=Number.isFinite(dayNumber)?h(`יום ${dayNumber}`,`Day ${dayNumber}`):plan.data.name;
  return <div className="workout-day-view"><Panel title={dayLabel} action={<Button variant="ghost" onClick={onClose}>{h("חזרה","Back")}</Button>}>
    <div className="workout-day-title">
      <div><p>{planTitle(plan.data.name)}</p><span>{plan.data.exercises.length} {h("תרגילים","exercises")}</span></div>
      <Button variant="outline" onClick={()=>onEdit()}>{h("עריכת היום","Edit day")}</Button>
    </div>
    <div className="workout-day-exercises">
      {plan.data.exercises.map((exercise,index)=><article key={exercise.id} className="workout-day-exercise">
        <span className="workout-day-index">{index+1}</span>
        <ExerciseThumbnail exercise={exercise}/>
        <div><h3>{exercise.name}</h3><p>{exercise.sets} × {exercise.holdSeconds?`${exercise.holdSeconds}${exercise.holdSecondsMax?`–${exercise.holdSecondsMax}`:""} ${h("שניות","sec")}`:`${exercise.reps}${exercise.repMax?`–${exercise.repMax}`:""} ${h("חזרות","reps")}`} {exercise.kind==="strength"&&!exercise.holdSeconds&&<>· {exercise.loadUnknown?h("משקל פתוח","Set load"):`${exercise.weight}${exercise.weightMax?`–${exercise.weightMax}`:""} kg`}</>}</p>{exercise.muscle&&<small>{exercise.muscle}</small>}</div>
        <button className="workout-exercise-edit" onClick={()=>onEdit(exercise.id)} aria-label={`${h("עריכת", "Edit")} ${exercise.name}`}>✎</button>
      </article>)}
    </div>
    {plan.data.notes&&<details className="workout-personal-note"><summary>{h("הנחיות התכנית","Program guidance")}</summary><p className="mt-3 whitespace-pre-wrap leading-7">{plan.data.notes}</p></details>}
    <Button className="workout-day-start" onClick={onStart}>{h("התחלת האימון","Start workout")}</Button>
  </Panel></div>;
}
function PlanEditor({
  existing,
  initialExerciseId,
  onClose,
}: {
  existing: HealthRow<"workout_plans"> | null;
  initialExerciseId?: string|null;
  onClose: () => void;
}) {
  const h = useHealthText();
  const [plan, setPlan] = useState<Payload<"workout_plans">>(
    existing?.data ?? { name: "", exercises: [], days: [], archived: false },
  );
  const [activePlanExercise,setActivePlanExercise]=useState<string|null>(initialExerciseId??existing?.data.exercises[0]?.id??null);
  const [error, setError] = useState<string | null>(null),
    [busy, setBusy] = useState(false);
  function add(c?: (typeof exerciseCatalog)[number]) {
    const exercise=exerciseSchema.parse({id:crypto.randomUUID(),name:c?h(c.he,c.en):h("תרגיל אישי","Custom exercise"),catalogId:c?.catalogId,demoId:c&&"demoId" in c?c.demoId:undefined,muscle:c?.muscle??"",equipment:c?.equipment??"",kind:c?.kind??"strength",...(c&&"demoId" in c&&c.demoId==="Plank"?{reps:1,holdSeconds:30,holdSecondsMax:45}:{})});
    setPlan(p=>({...p,exercises:[...p.exercises,exercise]}));
    setActivePlanExercise(exercise.id);
  }
  function patch(id: string, values: Partial<Exercise>) {
    setPlan((p) => ({
      ...p,
      exercises: p.exercises.map((e) =>
        e.id === id ? { ...e, ...values } : e,
      ),
    }));
  }
  function move(index: number, offset: number) {
    setPlan((p) => {
      const list = [...p.exercises];
      const target = index + offset;
      if (target < 0 || target >= list.length) return p;
      [list[index], list[target]] = [list[target], list[index]];
      return { ...p, exercises: list };
    });
  }
  async function persist(archive = false) {
    setBusy(true);
    try {
      await useHealthStore
        .getState()
        .save(
          "workout_plans",
          { ...plan, archived: archive },
          existing?.id ? existing : undefined,
        );
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    } finally {
      setBusy(false);
    }
  }
  return (
    <Panel
      title={h("בניית תכנית", "Plan builder")}
      action={
        <Button variant="ghost" onClick={onClose}>
          {h("סגירה", "Close")}
        </Button>
      }
    >
      <div className="grid gap-4">
        <ErrorText error={error} />
        <details className="workout-personal-note"><summary>{h("הנחיות ותזמון", "Instructions & schedule")}</summary><label className="mt-3 grid gap-2 text-sm">{h("הנחיות התכנית", "Program instructions")}<textarea className="w-full rounded-2xl border bg-background p-3 leading-7" rows={5} value={plan.notes??""} onChange={e=>setPlan(p=>({...p,notes:e.target.value}))}/></label>
        <fieldset>
          <legend className="mb-2 text-sm text-muted-foreground">
            {h("ימים מתוכננים", "Scheduled days")}
          </legend>
          <div className="flex flex-wrap gap-3">
            {daysHe.map((day, i) => (
              <label key={i} className="flex items-center gap-1.5 text-sm">
                <input
                  type="checkbox"
                  checked={plan.days.includes(i)}
                  onChange={(e) =>
                    setPlan((p) => ({
                      ...p,
                      days: e.target.checked
                        ? [...p.days, i]
                        : p.days.filter((d) => d !== i),
                    }))
                  }
                />
                {h(day, daysEn[i])}
              </label>
            ))}
          </div>
        </fieldset></details>
        <Field
          label={h("שם התכנית", "Plan name")}
          value={plan.name}
          onChange={(e) => setPlan((p) => ({ ...p, name: e.target.value }))}
        />

        <details>
          <summary>{h("קטלוג תרגילים", "Exercise catalog")}</summary>
          <div className="mt-3 flex flex-wrap gap-2">
            {exerciseCatalog.map((c) => (
              <Button
                key={c.en}
                variant="outline"
                size="sm"
                onClick={() => add(c)}
              >
                {h(c.he, c.en)}
              </Button>
            ))}
          </div>
        </details>
        <Button variant="outline" onClick={() => add()}>
          {h("הוספת תרגיל אישי", "Add custom exercise")}
        </Button>
        {plan.exercises.map((e, index) => (
          <article key={e.id} className="workout-exercise-card">
            <button className="workout-exercise-heading" aria-expanded={activePlanExercise===e.id} onClick={()=>setActivePlanExercise(activePlanExercise===e.id?null:e.id)}><ExerciseThumbnail exercise={e}/><span className="flex-1 text-start font-semibold">{e.name}<small className="mt-1 block text-xs font-normal text-muted-foreground">{e.sets} × {e.holdSeconds?`${e.holdSeconds}s`:e.reps} · {e.loadUnknown?h("משקל פתוח", "Set load"):`${e.weight} kg`}</small></span><span>{activePlanExercise===e.id?"−":"+"}</span></button>
            {activePlanExercise===e.id&&<div className="workout-exercise-body grid gap-3">
            <div className="flex flex-wrap gap-2">
              <Button
                size="sm"
                variant="ghost"
                disabled={index === 0}
                aria-label={h("הזזת תרגיל למעלה", "Move exercise up")}
                onClick={() => move(index, -1)}
              >
                ↑
              </Button>
              <Button
                size="sm"
                variant="ghost"
                disabled={index === plan.exercises.length - 1}
                aria-label={h("הזזת תרגיל למטה", "Move exercise down")}
                onClick={() => move(index, 1)}
              >
                ↓
              </Button>
              <Button
                size="sm"
                variant="ghost"
                onClick={() =>
                  setPlan((p) => ({
                    ...p,
                    exercises: p.exercises.filter((x) => x.id !== e.id),
                  }))
                }
              >
                {h("הסרה", "Remove")}
              </Button>
            </div>
            <ExerciseDemo exercise={e}/>
            <SelectField label={h("המחשה לתרגיל", "Exercise demonstration")} value={resolveExerciseDemo(e)?.id??""} onChange={event=>patch(e.id,{demoId:event.target.value||undefined})}><option value="">{h("בחירה אוטומטית לפי שם", "Automatic by name")}</option>{demos.map(d=><option key={d.id} value={d.id}>{h(d.he,d.en)}</option>)}</SelectField>
            <Field
              label={h("שם התרגיל", "Exercise name")}
              value={e.name}
              onChange={(x) => patch(e.id, { name: x.target.value, demoId: undefined, catalogId: undefined })}
            />
            <div className="grid grid-cols-2 gap-3">
              <Field
                label={h("קבוצת שרירים", "Muscle group")}
                value={e.muscle}
                onChange={(x) => patch(e.id, { muscle: x.target.value })}
              />
              <Field
                label={h("ציוד", "Equipment")}
                value={e.equipment}
                onChange={(x) => patch(e.id, { equipment: x.target.value })}
              />
              <SelectField
                label={h("סוג", "Type")}
                value={e.kind}
                onChange={(x) =>
                  patch(e.id, { kind: x.target.value as Exercise["kind"] })
                }
              >
                <option value="strength">{h("כוח", "Strength")}</option>
                <option value="cardio">{h("אירובי", "Cardio")}</option>
              </SelectField>
              <Field
                label={h("סטים", "Sets")}
                type="number"
                min={1}
                max={30}
                value={e.sets}
                onChange={(x) => patch(e.id, { sets: +x.target.value })}
              />
              {(e.holdSeconds ? ([["holdSeconds",h("משך בשניות","Duration (seconds)")]] as const) : e.kind === "strength"
                ? ([
                    ["reps", h("חזרות", "Reps")],
                    ["weight", h("משקל בק״ג", "Weight (kg)")],
                  ] as const)
                : ([
                    ["duration", h("משך בדקות", "Duration (min)")],
                    ["distance", h("מרחק בק״מ", "Distance (km)")],
                  ] as const)
              ).map(([key, label]) => (
                <Field
                  key={key}
                  label={label}
                  type="number"
                  min={0}
                  step={key === "reps" ? 1 : 0.1}
                  value={key === "weight" && e.loadUnknown ? "" : e[key]}
                  onChange={(x) => patch(e.id, { [key]: +x.target.value, ...(key === "weight" ? {loadUnknown: !x.target.value, weightMax: undefined} : {}) })}
                />
              ))}
              {e.repMax!==undefined && <Field label={h("חזרות עד", "Maximum reps")} type="number" min={e.reps} value={e.repMax} onChange={x=>patch(e.id,{repMax:+x.target.value})}/>}
              {e.weightMax!==undefined && <Field label={h("משקל עד", "Maximum load")} type="number" min={e.weight} step="0.5" value={e.weightMax} onChange={x=>patch(e.id,{weightMax:+x.target.value})}/>}
              {e.holdSecondsMax!==undefined && <Field label={h("משך מרבי בשניות", "Maximum seconds")} type="number" min={e.holdSeconds} value={e.holdSecondsMax} onChange={x=>patch(e.id,{holdSecondsMax:+x.target.value})}/>}
              <Field
                label={h("מנוחה בשניות", "Rest (seconds)")}
                type="number"
                min={0}
                max={1800}
                value={e.rest}
                onChange={(x) => patch(e.id, { rest: +x.target.value })}
              />
            </div>
            <Field
              label={h("הערות", "Notes")}
              value={e.notes}
              onChange={(x) => patch(e.id, { notes: x.target.value })}
            />
            </div>}
          </article>
        ))}
        <div className="flex flex-wrap gap-2">
          <Button
            disabled={busy || !plan.name || !plan.exercises.length}
            onClick={() => void persist()}
          >
            {h("שמירת תכנית", "Save plan")}
          </Button>
          {existing?.id && (
            <Button
              variant="outline"
              disabled={busy}
              onClick={() => void persist(true)}
            >
              {h("העברה לארכיון", "Archive plan")}
            </Button>
          )}
        </div>
      </div>
    </Panel>
  );
}
function SessionEditor({
  row,
  onClose,
}: {
  row: HealthRow<"workout_sessions">;
  onClose: () => void;
}) {
  const h = useHealthText();
  const owner = useHealthStore((s) => s.owner);
  const cacheKey = `kh-health-draft:${owner}:${row.id}`;
  const [draft] = useState(() => {
    try {
      const cached = JSON.parse(sessionStorage.getItem(cacheKey) ?? "null");
      if (cached?.version && cached?.data)
        return {
          version: cached.version as number,
          data: cached.data as Payload<"workout_sessions">,
        };
    } catch {
      /* Ignore an unreadable local draft. */
    }
    return { version: row.version, data: row.data };
  });
  const [session, setSession] = useState<Payload<"workout_sessions">>(
    draft.data,
  );
  const [addingExercise,setAddingExercise]=useState(false);
  const [exerciseQuery,setExerciseQuery]=useState("");
  const [activeExercise,setActiveExercise]=useState<string|null>(row.data.exercises[0]?.id??null);
  const [error, setError] = useState<string | null>(null),
    [busy, setBusy] = useState(false),
    [deadline, setDeadline] = useState<number | null>(null),
    [remaining, setRemaining] = useState(0);
  useEffect(() => {
    sessionStorage.setItem(
      cacheKey,
      JSON.stringify({ version: draft.version, data: session }),
    );
  }, [cacheKey, session, draft.version]);
  useEffect(() => {
    if (!deadline) return;
    const tick = () => {
      const left = Math.max(0, Math.ceil((deadline - Date.now()) / 1000));
      setRemaining(left);
      if (!left) setDeadline(null);
    };
    tick();
    const timer = setInterval(tick, 1000);
    return () => clearInterval(timer);
  }, [deadline]);
  const data = useHealthStore((s) => s.data);
  const prior = data.workout_sessions
    .filter(
      (s) =>
        s.id !== row.id &&
        s.data.status !== "cancelled" &&
        s.data.date <= row.data.date,
    )
    .sort((a, b) => b.data.startedAt.localeCompare(a.data.startedAt));
  function patchExercise(
    id: string,
    fn: (e: PerformedExercise) => PerformedExercise,
  ) {
    setSession((s) => ({
      ...s,
      exercises: s.exercises.map((e) => (e.id === id ? fn(e) : e)),
    }));
  }
  async function persist(status: Payload<"workout_sessions">["status"]) {
    setBusy(true);
    try {
      await useHealthStore.getState().save(
        "workout_sessions",
        {
          ...session,
          status,
          endedAt: status === "active" ? null : new Date().toISOString(),
        },
        { ...row, version: draft.version },
      );
      sessionStorage.removeItem(cacheKey);
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    } finally {
      setBusy(false);
    }
  }
  async function discard() {
    setBusy(true);
    try {
      await useHealthStore.getState().remove("workout_sessions",row);
      sessionStorage.removeItem(cacheKey);
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    } finally {
      setBusy(false);
    }
  }
  function addExercise(c?: (typeof exerciseCatalog)[number]) {
    const e = exerciseSchema.parse({
      id: crypto.randomUUID(),
      name: c?h(c.he,c.en):h("תרגיל נוסף", "Additional exercise"),
      catalogId:c?.catalogId,
      demoId:c&&"demoId" in c?c.demoId:undefined,
      kind:c?.kind??"strength",sets:1,
      ...(c&&"demoId" in c&&c.demoId==="Plank"?{reps:1,holdSeconds:30,holdSecondsMax:45}:{}),
    });
    setAddingExercise(false);
    setActiveExercise(e.id);
    setSession((s) => ({
      ...s,
      quick: false,
      exercises: [
        ...s.exercises,
        {
          ...e,
          skipped: false,
          performed: [
            {
              id: crypto.randomUUID(),
              reps: e.reps,
              seconds: e.holdSeconds,
              weight: 0,
              done: false,
              duration: 0,
              distance: 0,
            },
          ],
        },
      ],
    }));
  }
  return (
    <div className="workout-session"><Panel
      title={session.name}
      action={
        <Button variant="ghost" onClick={onClose}>
          {h("סגירה — טיוטה נשמרת", "Close — keep draft")}
        </Button>
      }
    >
      <div className="grid gap-4">
        <ErrorText error={error} />
        {session.programNotes?.includes("הקרנה")&&<details className="workout-personal-note"><summary>{h("דגשים אישיים", "Personal guidance")}</summary><p className="mt-2 text-sm leading-7">{h("כאבי גב עם הקרנה: אין לבצע תרגיל שמחמיר כאב או הקרנה. אם התסמינים עדיין קיימים, יש לפנות להערכה רפואית לפני חזרה לעומס.", "Back pain with radiating symptoms: stop exercises that worsen pain or radiation. Seek medical evaluation before loading if symptoms persist.")}</p></details>}
        <details className="workout-personal-note"><summary>{session.date} · {h("שינוי תאריך", "Change date")}</summary>
        <Field
          label={h("תאריך הביצוע", "Workout date")}
          type="date"
          value={session.date}
          onChange={(e) => setSession((s) => ({ ...s, date: e.target.value }))}
        />
        </details>
        {deadline && (
          <div
            role="timer"
            className="rounded-xl bg-primary/10 p-4 text-center text-2xl tabular-nums"
          >
            {Math.floor(remaining / 60)}:
            {String(remaining % 60).padStart(2, "0")}{" "}
            <Button variant="ghost" size="sm" onClick={() => setDeadline(null)}>
              {h("עצירה", "Stop")}
            </Button>
          </div>
        )}
        {session.exercises.map((e) => {
          const nextSet=e.performed.find(s=>!s.done)??e.performed.at(-1);
          const last = prior
            .flatMap((s) => s.data.exercises)
            .find((x) => x.name === e.name && !x.skipped);
          return (
            <article key={e.id} className={`workout-exercise-card ${activeExercise===e.id?"is-open":""}`}>
              <button className="workout-exercise-heading" aria-expanded={activeExercise===e.id} onClick={()=>setActiveExercise(activeExercise===e.id?null:e.id)}>
                <ExerciseThumbnail exercise={e}/><span className="flex-1 text-start"><h3 className="font-semibold">{e.name}</h3><span className="block mt-1 text-xs text-muted-foreground">{e.performed.filter(s=>s.done).length}/{e.performed.length} {h("סטים", "sets")} · {e.holdSeconds ? `${nextSet?.seconds??e.holdSeconds}s` : `${nextSet?.reps??e.reps} ${h("חזרות","reps")} · ${e.loadUnknown&&!nextSet?.loadConfirmed?h("משקל פתוח","Set load"):`${nextSet?.weight??e.weight} kg`}`}</span></span><span aria-hidden="true">{activeExercise===e.id?"−":"+"}</span>
              </button>
              {activeExercise===e.id&&<div className="workout-exercise-body">
              <ExerciseDemo exercise={e}/>
              <details className="workout-exercise-options"><summary>{h("עריכת תרגיל והסרה", "Edit or remove exercise")}</summary>
              <Field
                label={h("תרגיל", "Exercise")}
                value={e.name}
                onChange={(x) =>
                  patchExercise(e.id, (v) => ({ ...v, name: x.target.value, demoId: undefined, catalogId: undefined }))
                }
              />
              <Button variant="destructive" size="sm" onClick={()=>{setSession(s=>({...s,exercises:s.exercises.filter(v=>v.id!==e.id)}));setActiveExercise(null)}}>{h("הסרת התרגיל מהאימון", "Remove exercise from workout")}</Button>
              {last && (
                <p className="mt-2 text-xs text-muted-foreground">
                  {h("בפעם הקודמת", "Last time")}:{" "}
                  {last.performed
                    .filter((s) => s.done)
                    .map((s) =>
                      e.holdSeconds ? `${s.seconds??e.holdSeconds}s` : e.kind === "strength"
                        ? `${s.reps} × ${s.weight} kg`
                        : `${s.duration} min / ${s.distance} km`,
                    )
                    .join(" · ") || "—"}
                </p>
              )}
              <label className="my-3 flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked={e.skipped}
                  onChange={(x) =>
                    patchExercise(e.id, (v) => ({
                      ...v,
                      skipped: x.target.checked,
                    }))
                  }
                />
                {h("דילוג על התרגיל", "Skip exercise")}
              </label>
              </details>
              {!e.skipped &&
                e.performed.map((s, index) => (
                  <div
                    key={s.id}
                    className="workout-set-row mb-2 grid grid-cols-[auto_1fr_1fr_auto] items-end gap-2"
                  >
                    <span className="pb-2 text-sm">{index + 1}</span>
                    {(e.holdSeconds ? ([["seconds",h("שניות","Seconds")]] as const) : e.kind === "strength"
                      ? ([
                          ["reps", h("חזרות", "Reps")],
                          ["weight", h("ק״ג", "kg")],
                        ] as const)
                      : ([
                          ["duration", h("דקות", "Minutes")],
                          ["distance", h("ק״מ", "km")],
                        ] as const)
                    ).map(([key, label]) => (
                      <Field
                        key={key}
                        label={label}
                        type="number"
                        min={0}
                        step={key === "reps" ? 1 : 0.1}
                        value={key === "weight" && e.loadUnknown && !s.loadConfirmed ? "" : s[key] ?? e.holdSeconds ?? 0}
                        onChange={(x) =>
                          patchExercise(e.id, (v) => ({
                            ...v,
                            performed: v.performed.map((set) =>
                              set.id === s.id
                                ? { ...set, [key]: +x.target.value, ...(key === "weight" ? {loadConfirmed:!!x.target.value} : {}) }
                                : set,
                            ),
                          }))
                        }
                      />
                    ))}
                    <label className="flex min-h-10 items-center gap-1 text-xs">
                      <input
                        type="checkbox"
                        aria-label={`${h("בוצע סט", "Set done")} ${index + 1} ${e.name}`}
                        checked={s.done}
                        onChange={(x) => {
                          if(x.target.checked && e.loadUnknown && !s.loadConfirmed){setError("load_required");return;}
                          setError(null);
                          patchExercise(e.id, (v) => ({
                            ...v,
                            performed: v.performed.map((set) =>
                              set.id === s.id
                                ? { ...set, done: x.target.checked }
                                : set,
                            ),
                          }));
                          if (x.target.checked && e.rest)
                            setDeadline(Date.now() + e.rest * 1000);
                        }}
                      />
                      ✓
                    </label>
                  </div>
                ))}
              <div className="flex flex-wrap gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  disabled={e.skipped}
                  onClick={() =>
                    patchExercise(e.id, (v) => ({
                      ...v,
                      performed: [
                        ...v.performed,
                        {
                          id: crypto.randomUUID(),
                          reps: e.reps,
                          weight: e.weight,
                          done: false,
                          seconds: e.holdSeconds,
                          duration: e.duration,
                          distance: e.distance,
                        },
                      ],
                    }))
                  }
                >
                  {h("הוספת סט", "Add set")}
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setDeadline(Date.now() + e.rest * 1000)}
                >
                  {h("מנוחה", "Rest")} {e.rest}s
                </Button>
              </div>
              </div>}
            </article>
          );
        })}
        {!session.quick && (
          <Button variant="outline" onClick={()=>setAddingExercise(v=>!v)}>
            {h("הוספת תרגיל לאימון", "Add exercise to workout")}
          </Button>
        )}
        {addingExercise&&<div className="workout-add-picker"><Field label={h("חיפוש תרגיל", "Find exercise")} value={exerciseQuery} onChange={event=>setExerciseQuery(event.target.value)}/><div className="mt-3 grid max-h-64 gap-2 overflow-y-auto">{exerciseCatalog.filter(c=>`${c.he} ${c.en}`.toLowerCase().includes(exerciseQuery.toLowerCase())).map(c=><button key={c.en} className="rounded-xl border p-3 text-start text-sm" onClick={()=>addExercise(c)}>{h(c.he,c.en)} <span className="float-end">＋</span></button>)}</div><Button variant="ghost" onClick={()=>addExercise()}>{h("תרגיל מותאם אישית", "Custom exercise")}</Button></div>}
        <fieldset className="grid gap-3 rounded-xl border p-4"><legend className="px-1 text-sm font-semibold">{h("איך היה האימון? (לשיפור ההמלצות)","How was your workout? (improves recommendations)")}</legend>
          <SelectField label={h("אנרגיה והתאוששות","Energy and readiness")} value={session.feedback?.energy??3} onChange={e=>setSession(s=>({...s,feedback:{energy:Number(e.target.value),rir:s.feedback?.rir??null,pain:s.feedback?.pain??false}}))}>{[1,2,3,4,5].map(n=><option key={n} value={n}>{n} / 5</option>)}</SelectField>
          <SelectField label={h("כמה חזרות עוד יכולת לבצע בסטים האחרונים?","Reps you could still do in the last sets (RIR)")} value={session.feedback?.rir??""} onChange={e=>setSession(s=>({...s,feedback:{energy:s.feedback?.energy??3,rir:e.target.value===""?null:Number(e.target.value),pain:s.feedback?.pain??false}}))}><option value="">{h("לא בטוח/ה","Not sure")}</option>{[0,1,2,3,4,5].map(n=><option key={n} value={n}>{n===5?"5+":n}</option>)}</SelectField>
          <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={session.feedback?.pain??false} onChange={e=>setSession(s=>({...s,feedback:{energy:s.feedback?.energy??3,rir:s.feedback?.rir??null,pain:e.target.checked}}))}/>{h("היה כאב באימון — לא להציע העלאת עומס","I experienced pain — do not suggest increasing load")}</label>
        </fieldset>
        <details className="workout-personal-note"><summary>{h("הערות ואפשרויות שמירה", "Notes & save options")}</summary>
        <Field
          label={h("הערות לאימון", "Workout notes")}
          value={session.notes}
          onChange={(e) => setSession((s) => ({ ...s, notes: e.target.value }))}
        />
        </details>
        <div className="workout-session-actions flex flex-wrap gap-2">
          <Button disabled={busy} onClick={() => void persist("completed")}>
            {h("סיום אימון", "Finish workout")}
          </Button>
          <Button
            variant="outline"
            disabled={busy}
            onClick={() => void persist("active")}
          >
            {h("שמירת התקדמות", "Save progress")}
          </Button>
          <details className="workout-extra-actions"><summary>{h("אפשרויות נוספות", "More options")}</summary>
          <Button
            variant="outline"
            disabled={busy}
            onClick={() => void persist("partial")}
          >
            {h("שמירה כחלקי", "Save partial")}
          </Button>
          <Button
            variant="ghost"
            disabled={busy}
            onClick={() => {
              if (window.confirm(h("לבטל ולמחוק את האימון מהתאריך הזה?", "Cancel and delete this workout from this date?")))
                void discard();
            }}
          >
            {h("ביטול ומחיקת אימון", "Cancel & delete workout")}
          </Button>
          </details>
        </div>
      </div>
    </Panel></div>
  );
}

"use client";
import { useEffect, useState } from "react";
import dynamic from "next/dynamic";
import Link from "next/link";
import { Leaf, Dumbbell, ChartNoAxesCombined, Settings2, ChevronRight } from "lucide-react";
import "./health.css";
import { Button } from "@/components/ui/button";
import { useHealthStore } from "@/lib/health/store";
import { calculateGoal, goalForDate, localDate } from "@/lib/health/calculations";
import { useHealthText } from "@/lib/health/i18n";
import { WeekPicker } from "./week-picker";
import { useAppStore } from "@/lib/store/app-store";
import { useIdentity } from "@/lib/identity";
import { healthFunction } from "@/lib/health/api";
import { ErrorText } from "./shared";
const Nutrition = dynamic(() => import("./nutrition").then((m) => m.Nutrition));
const Workouts = dynamic(() => import("./workouts").then((m) => m.Workouts));
const HealthProgress = dynamic(() =>
  import("./progress").then((m) => m.HealthProgress),
);
const HealthSettings = dynamic(() =>
  import("./settings").then((m) => m.HealthSettings),
);
let automaticGoalBusy = false;
async function refreshAutomaticGoal() {
  if (automaticGoalBusy) return;
  automaticGoalBusy = true;
  try { await updateAutomaticGoal(); } finally { automaticGoalBusy = false; }
}
async function updateAutomaticGoal() {
  const state = useHealthStore.getState();
  const profile = state.data.health_profiles[0]?.data;
  if (!state.owner || !profile?.birthDate || !profile.nutritionEnabled) return;
  const today = localDate(profile.timezone);
  const current = goalForDate(state.data.nutrition_goals.map(g=>g.data), today);
  if(current?.method !== "calculated") return;
  try {
    const next = calculateGoal(profile,today);
    if ((["kcal","protein","carbs","fat"] as const).some(k=>next[k]!==current[k])) {
      await state.save("nutrition_goals",next,state.data.nutrition_goals.find(g=>g.data.date===today));
    }
  } catch { /* Incomplete profiles keep their last confirmed goal. */ }
}
export function HealthPage() {
  const h = useHealthText();
  const state = useHealthStore(),
    identity = useIdentity((s) => s.actingMemberId);
  const memberName=useAppStore(s=>identity?s.members[identity]?.display_name:undefined)?.trim();
  const [workoutFocus,setWorkoutFocus]=useState(false);
  const [tab, setTab] = useState("home"),
    [pickedDate, setDate] = useState<string | null>(null);
  const profile = state.data.health_profiles[0]?.data;
  const date = pickedDate ?? localDate(profile?.timezone ?? "Asia/Jerusalem");
  useEffect(() => {
    void useHealthStore
      .getState()
      .boot()
      .then(() => {
        void refreshAutomaticGoal();
        void healthFunction("health-account", { action: "cleanup" }).catch(
          () => {},
        );
      });
    const refresh = () => {
      if (document.visibilityState === "visible")
        void useHealthStore
          .getState()
          .flush()
          .then(() => useHealthStore.getState().refresh())
          .then(() => refreshAutomaticGoal());
    };
    window.addEventListener("online", refresh);
    document.addEventListener("visibilitychange", refresh);
    const timer = setInterval(refresh, 30000);
    return () => {
      window.removeEventListener("online", refresh);
      document.removeEventListener("visibilitychange", refresh);
      clearInterval(timer);
    };
  }, [identity]);
  const tabs = [
    ...(profile?.nutritionEnabled
      ? [["nutrition", h("תזונה", "Nutrition")]]
      : []),
    ...(profile?.workoutsEnabled
      ? [["workouts", h("אימונים", "Workouts")]]
      : []),
    ...(profile?.nutritionEnabled || profile?.workoutsEnabled
      ? [["progress", h("התקדמות", "Progress")]]
      : []),
    ["settings", h("הגדרות", "Settings")],
  ];
  const icons = { nutrition: Leaf, workouts: Dumbbell, progress: ChartNoAxesCombined, settings: Settings2 };
  const active = tabs.some(([key]) => key === tab) ? tab : profile?.nutritionEnabled && state.data.nutrition_goals.length ? "nutrition" : !profile?.nutritionEnabled && profile?.workoutsEnabled ? "workouts" : "settings";
  return (
    <div className="health-app flex min-h-screen flex-1 flex-col">
      <header className="health-topbar">
        <Link href="/" className="health-back"><ChevronRight size={17}/>{h("חזרה לבית", "Smart Home")}</Link>
        <Link href="/health" className="health-wordmark"><span className="health-mark"><Leaf size={20}/></span> KH <span>WELLNESS</span></Link>
        <button className="health-profile" onClick={()=>setTab("settings")} aria-label={h("הגדרות אישיות", "Personal settings")}><Settings2 size={20}/></button>
      </header>
      <main className="mx-auto w-full max-w-3xl flex-1 px-5 pt-7 pb-32 sm:px-8">
        {!workoutFocus&&<>
        <div className="mb-7 flex items-end justify-between gap-3">
          <div><p className="health-eyebrow">{h("קצת יותר טוב. בכל יום.", "A little better. Every day.")}</p>
          <h1 aria-label={h("הבריאות שלי", "My health")} className="mt-2 text-3xl font-bold tracking-tight sm:text-4xl">{memberName ? `${h("שלום", "Hello")}, ${memberName}` : h("שלום", "Hello")}<span aria-hidden="true" className="health-dot">.</span></h1></div>
        </div>
        </>}
        {active !== "settings" && !workoutFocus && <WeekPicker date={date} today={localDate(profile?.timezone??"Asia/Jerusalem")} onChange={setDate}/>}
        {state.pending > 0 && (
          <p
            role="status"
            className="mb-3 rounded-xl bg-amber-500/10 p-3 text-sm"
          >
            {state.pending}{" "}
            {h(
              "פעולות ממתינות לסנכרון. הן שמורות במכשיר הזה.",
              "changes pending sync, saved on this device.",
            )}
          </p>
        )}
        <ErrorText error={state.error} />
        {state.conflict && (
          <div className="my-3 flex flex-wrap gap-2">
            <Button
              variant="outline"
              onClick={() => void state.resolveConflict(false)}
            >
              {h("שימוש בגרסה מהשרת", "Use server version")}
            </Button>
            <Button onClick={() => void state.resolveConflict(true)}>
              {h("שמירת השינויים שלי", "Keep my changes")}
            </Button>
          </div>
        )}
        {state.loading ? (
          <p role="status" className="py-16 text-center">
            {h("טוען את האזור האישי…", "Loading your personal area…")}
          </p>
        ) : !state.owner ? (
          <Button className="mt-4" onClick={() => void state.boot()}>
            {h("ניסיון נוסף", "Retry")}
          </Button>
        ) : (
          <>
            <div
              role="tablist"
              aria-label={h("אזור הבריאות", "Health area")}
              className="health-bottom-nav"
            >
              {tabs.map(([key, title]) => { const Icon = icons[key as keyof typeof icons]; return (
                <button
                  key={key}
                  type="button"
                  id={`health-tab-${key}`}
                  role="tab"
                  aria-selected={active === key}
                  aria-controls="health-content"
                  onClick={() => setTab(key)}
                  className={`health-nav-item ${active === key ? "is-active" : ""}`}
                >
                  <Icon size={22}/><span>{title}</span>
                </button>
              );})}
            </div>
            <div
              id="health-content"
              key={active}
              className="health-screen"
              role="tabpanel"
              aria-labelledby={`health-tab-${active}`}
            >
              {active === "settings" && <HealthSettings key={state.owner} />}
              {active === "nutrition" && <Nutrition key={state.owner} date={date} onWorkout={()=>setTab(profile?.workoutsEnabled ? "workouts" : "settings")} />}{" "}
              {active === "workouts" && (
                <Workouts key={state.owner} date={date} onFocusChange={setWorkoutFocus} />
              )}{" "}
              {active === "progress" && <HealthProgress date={date} />}
            </div>
          </>
        )}
      </main>
    </div>
  );
}

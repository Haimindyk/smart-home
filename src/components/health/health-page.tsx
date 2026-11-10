"use client";
import { useEffect, useState } from "react";
import dynamic from "next/dynamic";
import Link from "next/link";
import { House, Dumbbell, ChartNoAxesCombined, Settings2, ChevronRight, MessageCircle, Plus } from "lucide-react";
import "./health.css";
import { Button } from "@/components/ui/button";
import { useHealthStore } from "@/lib/health/store";
import { calculateGoal, goalForDate, localDate } from "@/lib/health/calculations";
import { useHealthText } from "@/lib/health/i18n";
import { MemberAvatar } from "@/components/identity/member-avatar";
import { WeekPicker } from "./week-picker";
import { useAppStore } from "@/lib/store/app-store";
import { useIdentity } from "@/lib/identity";
import { healthFunction } from "@/lib/health/api";
import { ErrorText } from "./shared";
const Nutrition = dynamic(() => import("./nutrition").then((m) => m.Nutrition));
const CoachChat = dynamic(() => import("./coach-chat").then(m=>m.CoachChat));
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
  const member=useAppStore(s=>identity?s.members[identity]:undefined);
  const memberName=member?.display_name?.trim();
  const [entryVersion,setEntryVersion]=useState(0),[addFood,setAddFood]=useState(false);
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
      ? [["nutrition", h("היום", "Today")]]
      : []),
    ...(profile?.workoutsEnabled
      ? [["workouts", h("אימונים", "Workouts")]]
      : []),
    ...(profile?.nutritionEnabled || profile?.workoutsEnabled
      ? [["progress", h("התקדמות", "Progress")]]
      : []),
    ...((profile?.nutritionEnabled||profile?.workoutsEnabled)?[["coach",h("צ׳אט AI","AI chat")]]:[]),
    ["settings", h("הגדרות", "Settings")],
  ];
  const icons = { coach:MessageCircle, nutrition: House, workouts: Dumbbell, progress: ChartNoAxesCombined, settings: Settings2 };
  const active = tabs.some(([key]) => key === tab) ? tab : profile?.nutritionEnabled && state.data.nutrition_goals.length ? "nutrition" : !profile?.nutritionEnabled && profile?.workoutsEnabled ? "workouts" : "settings";
  return (
    <div className="health-app flex min-h-screen flex-1 flex-col" data-health-section={active} data-can-add={!!profile?.nutritionEnabled && !workoutFocus}>
      <header className="health-topbar health-compact-header">
        <span className="health-avatar" aria-hidden="true"><MemberAvatar member={member} className="size-11" emojiClassName="text-3xl"/></span>
        <div className="health-header-copy"><h1 id="health-page-title">{active === "nutrition" ? (memberName ? `${h("שלום", "Hello")} ${memberName},` : h("היום שלך", "Your day")) : active === "coach" ? h("צ׳אט AI", "AI chat") : active === "workouts" ? h("האימונים שלך", "Your workouts") : active === "progress" ? h("ההתקדמות שלך", "Your progress") : h("הגדרות אישיות", "Personal settings")}</h1><p>{active === "nutrition" || active === "progress" ? new Intl.DateTimeFormat(h("he-IL","en-US"),{month:"long",day:"numeric",timeZone:"UTC"}).format(new Date(`${date}T12:00:00Z`)) : active === "coach" ? h("תזונה, אימונים וטכניקה", "Food, training and technique") : active === "workouts" ? h("הקצב שלך, ההתקדמות שלך", "Your pace, your progress") : h("הכול במקום אחד", "Everything in one place")}</p></div>
        <div className="health-header-actions"><button id="health-settings-button" className="health-profile" onClick={()=>setTab("settings")} aria-label={h("הגדרות אישיות", "Personal settings")} aria-pressed={active==="settings"}><Settings2 size={21}/></button><Link href="/" className="health-back" aria-label={h("חזרה לבית", "Smart Home")}><ChevronRight size={20}/></Link></div>
      </header>
      <main className="mx-auto w-full max-w-3xl flex-1 px-5 pt-5 pb-32 sm:px-8">
        {active !== "settings" && active !== "coach" && !workoutFocus && <WeekPicker date={date} today={localDate(profile?.timezone??"Asia/Jerusalem")} onChange={setDate}/>}
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
            {(profile?.nutritionEnabled || profile?.workoutsEnabled) && <div
              role="tablist"
              aria-label={h("אזור הבריאות", "Health area")}
              className="health-bottom-nav"
            >
              {tabs.filter(([key])=>key!=="settings").map(([key, title]) => { const Icon = icons[key as keyof typeof icons]; return (
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
            </div>}
            {profile?.nutritionEnabled && !workoutFocus && <button type="button" className="health-global-add" aria-label={h("הוספת ארוחה", "Add meal")} onClick={()=>{setEntryVersion(v=>v+1);setAddFood(true);setTab("nutrition")}}><Plus size={32}/></button>}
            <div
              id="health-content"
              key={active}
              className="health-screen"
              role="tabpanel"
              aria-labelledby={active === "settings" ? "health-page-title" : `health-tab-${active}`}
            >
              {active === "coach" && <CoachChat key={state.owner} onNavigate={key=>setTab(key==="nutrition"&&!profile?.nutritionEnabled||key==="workouts"&&!profile?.workoutsEnabled?"settings":key)}/>}
              {active === "settings" && <HealthSettings key={state.owner} />}
              {active === "nutrition" && <Nutrition key={state.owner} date={date} initialAdd={addFood} addRequest={entryVersion} onAddClosed={()=>setAddFood(false)}/>}{" "}
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

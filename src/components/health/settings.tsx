"use client";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { useHealthStore } from "@/lib/health/store";
import { profileSchema, type Payload } from "@/lib/health/model";
import { csvEscape } from "@/lib/health/calculations";
import { useHealthText } from "@/lib/health/i18n";
import { healthFunction } from "@/lib/health/api";
import { ProfileJourney } from "./profile-journey";
import { Field, Panel, SelectField, ErrorText } from "./shared";
export function HealthSettings() {
  const h = useHealthText();
  const data = useHealthStore((s) => s.data),
    save = useHealthStore((s) => s.save);
  const row = data.health_profiles[0];
  const [profileBase, setProfileBase] = useState(row);
  const [goalBases, setGoalBases] = useState(() => data.nutrition_goals);
  const [profile, setProfile] = useState(
    () => row?.data ?? profileSchema.parse({}),
  );
  const [error, setError] = useState<string | null>(null),
    [busy, setBusy] = useState(false),
    [notice, setNotice] = useState("");
  const [deleteModule, setDeleteModule] = useState("nutrition"),
    [confirm, setConfirm] = useState("");
  const patch = (key: string, value: unknown) =>
    setProfile((p) => ({ ...p, [key]: value }));
  async function persist() {
    setBusy(true);
    setError(null);
    try {
      const saved = await save("health_profiles", profile, profileBase);
      setProfileBase(saved);
      setNotice(
        h(
          "ההגדרות נשמרו. פעולות ללא רשת יסתנכרנו בחיבור הבא.",
          "Settings saved. Offline changes sync when connected.",
        ),
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    } finally {
      setBusy(false);
    }
  }
  async function saveProfileAndGoal(goal: Payload<"nutrition_goals">) {
    setBusy(true);setError(null);setNotice("");
    try {
      const savedProfile=await save("health_profiles", profile, profileBase);
      setProfileBase(savedProfile);
      const savedGoal=await save("nutrition_goals",goal,goalBases.find(g=>g.data.date===goal.date));
      setGoalBases(rows=>[...rows.filter(r=>r.data.date!==goal.date),savedGoal]);
      setNotice(h("הכול מוכן! הפרופיל והיעדים שלך נשמרו.", "You're all set! Your profile and targets are saved."));
    } catch(e) {setError(e instanceof Error?e.message:"failed");}
    finally {setBusy(false);}
  }
  function exportCsv() {
    const lines = [["table", "id", "date", "data"].map(csvEscape).join(",")];
    for (const [table, rows] of Object.entries(data))
      for (const r of rows)
        lines.push(
          [
            table,
            r.id,
            "date" in r.data ? r.data.date : "",
            JSON.stringify(r.data),
          ]
            .map(csvEscape)
            .join(","),
        );
    const url = URL.createObjectURL(
      new Blob(["\uFEFF" + lines.join("\r\n")], {
        type: "text/csv;charset=utf-8",
      }),
    );
    const a = document.createElement("a");
    a.href = url;
    a.download = "my-health.csv";
    a.click();
    URL.revokeObjectURL(url);
  }
  async function erase() {
    if (confirm !== "DELETE") return;
    setBusy(true);
    setError(null);
    try {
      if (useHealthStore.getState().pending) throw new Error("sync_failed");
      await healthFunction("health-account", {
        action: "delete",
        module: deleteModule,
      });
      await useHealthStore.getState().reset();
      await useHealthStore.getState().boot();
      setConfirm("");
      setNotice(h("הנתונים נמחקו.", "Data deleted."));
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="grid gap-5">
      <ErrorText error={error} />
      {notice && (
        <p role="status" className="rounded-xl bg-primary/10 p-3 text-sm">
          {notice}
        </p>
      )}
      <Panel title={h("הגדרות אישיות", "Personal settings")}>
        <div className="grid gap-4">
          <label className="flex cursor-pointer items-center justify-between gap-3 rounded-2xl border bg-muted/30 p-4 has-checked:border-foreground has-checked:bg-amber-50">
            <input
              type="checkbox"
              checked={profile.nutritionEnabled}
              onChange={(e) => patch("nutritionEnabled", e.target.checked)}
            />
            {h("הפעלת מעקב תזונה", "Enable nutrition tracking")}
          </label>
          <label className="flex cursor-pointer items-center justify-between gap-3 rounded-2xl border bg-muted/30 p-4 has-checked:border-foreground has-checked:bg-amber-50">
            <input
              type="checkbox"
              checked={profile.workoutsEnabled}
              onChange={(e) => patch("workoutsEnabled", e.target.checked)}
            />
            {h("הפעלת מעקב אימונים", "Enable workout tracking")}
          </label>
          <Button disabled={busy} onClick={() => void persist()}>
            {h("שמירת הגדרות", "Save settings")}
          </Button>
        </div>
      </Panel>
      <ProfileJourney profile={profile} onChange={setProfile} goals={data.nutrition_goals.map(g=>g.data)} onSave={saveProfileAndGoal} busy={busy}/>
      <details className="rounded-3xl border bg-card p-5"><summary className="font-semibold">{h("העדפות נוספות", "More preferences")}</summary><div className="mt-5 grid gap-4">          <Field
            label={h("אזור זמן", "Time zone")}
            value={profile.timezone}
            onChange={(e) => patch("timezone", e.target.value)}
          />
          <p className="text-sm text-muted-foreground">
            {h(
              "כיבוי מודול מסתיר אותו ושומר את ההיסטוריה. הנתונים אינם משותפים לבית. מי שיודע את ה־PIN שלך יכול להיכנס בשמך.",
              "Disabling a module keeps its history. Data is not shared with the household. Anyone who knows your PIN can sign in as you.",
            )}
          </p>
<Field label={h("יעד מים במ״ל", "Water target (ml)")} type="number" min={250} max={10000} value={profile.waterTarget} onChange={e=>patch("waterTarget",+e.target.value)}/><Button disabled={busy} onClick={()=>void persist()}>{h("שמירת העדפות", "Save preferences")}</Button></div></details>
      {data.nutrition_goals.length>0 && <details className="rounded-3xl border bg-card p-5"><summary className="font-semibold">{h("היסטוריית יעדים", "Goal history")}</summary>{[...data.nutrition_goals].sort((a,b)=>b.data.date.localeCompare(a.data.date)).map(g=><p className="mt-3 text-sm" key={g.id}>{g.data.date} · {g.data.kcal} kcal · P {g.data.protein} / C {g.data.carbs} / F {g.data.fat}</p>)}</details>}
      <Panel title={h("הנתונים שלך", "Your data")}>
        <Button variant="outline" onClick={exportCsv}>
          {h("ייצוא CSV", "Export CSV")}
        </Button>
        <details className="mt-5">
          <summary className="text-destructive">
            {h("מחיקת נתונים", "Delete data")}
          </summary>
          <div className="mt-3 grid gap-3">
            <SelectField
              label={h("מה למחוק?", "What to delete?")}
              value={deleteModule}
              onChange={(e) => setDeleteModule(e.target.value)}
            >
              <option value="nutrition">
                {h("תזונה ותמונות", "Nutrition & photos")}
              </option>
              <option value="workouts">{h("אימונים", "Workouts")}</option>
              <option value="all">
                {h("כל הנתונים האישיים", "All personal health data")}
              </option>
            </SelectField>
            <Field
              label={h(
                "לאישור מחיקה בלתי הפיכה יש להקליד DELETE",
                "Type DELETE to confirm permanent deletion",
              )}
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
            />
            <Button
              variant="destructive"
              disabled={busy || confirm !== "DELETE"}
              onClick={() => void erase()}
            >
              {h("מחיקה לצמיתות", "Delete permanently")}
            </Button>
          </div>
        </details>
      </Panel>
    </div>
  );
}

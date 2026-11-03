"use client";
import { useEffect, useState } from "react";
import { Camera, ArrowUpLeft, Flame, Beef, Wheat, Droplet, Plus, Search, Bookmark, PenLine, Dumbbell } from "lucide-react";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { useHealthStore } from "@/lib/health/store";
import {
  profileSchema,
  type HealthRow,
  type MealItem,
  type Nutrients,
  type Payload,
} from "@/lib/health/model";
import {
  goalForDate,
  mealNutrients,
  scaleNutrients,
  sumNutrients,
} from "@/lib/health/calculations";
import { analyzeMeal, uploadMealImage } from "@/lib/health/api";
import { createClient } from "@/lib/supabase/client";
import { useHealthText } from "@/lib/health/i18n";
import { Panel, Field, SelectField, Empty, ErrorText, round } from "./shared";
import { FoodPicker } from "./food-picker";
import { FoodLibrary } from "./food-library";
import { NutrientRing } from "./nutrient-ring";
const kinds = ["breakfast", "lunch", "dinner", "snack"] as const;
function MealImage({ path }: { path: string }) {
  const [url, setUrl] = useState("");
  const h = useHealthText();
  useEffect(() => {
    let cancelled = false;
    void createClient()
      .storage.from("health-images")
      .createSignedUrl(path, 300)
      .then(({ data }) => {
        if (!cancelled) setUrl(data?.signedUrl ?? "");
      });
    return () => {
      cancelled = true;
    };
  }, [path]);
  return url ? (
    <a
      href={url}
      target="_blank"
      rel="noreferrer"
      className="text-sm underline"
    >
      {h("הצגת תמונת הארוחה", "View meal photo")}
    </a>
  ) : null;
}
export function Nutrition({ date, onWorkout }: { date: string; onWorkout?:()=>void }) {
  const h = useHealthText();
  const data = useHealthStore((s) => s.data),
    save = useHealthStore((s) => s.save),
    remove = useHealthStore((s) => s.remove);
  const profile = data.health_profiles[0]?.data ?? profileSchema.parse({});
  const [addMenu,setAddMenu]=useState(false);
  const [foodMode,setFoodMode]=useState<"search"|"saved"|"manual">("search");
  function openEntry(mode: "photo"|"search"|"saved"|"manual") {setAddMenu(false);setEditing(null);setCapture(mode==="photo");setFoodMode(mode==="photo"?"search":mode);setEditor(true)}
  const [capture, setCapture] = useState(false);
  const [editing, setEditing] = useState<HealthRow<"meals"> | null>(null),
    [editor, setEditor] = useState(false),
    [error, setError] = useState<string | null>(null);
  const [weight, setWeight] = useState(""),
    [water, setWater] = useState(250);
  const meals = data.meals.filter((m) => m.data.date === date);
  const goal = goalForDate(
    data.nutrition_goals.map((g) => g.data),
    date,
  );
  const totals = sumNutrients(meals.map((m) => mealNutrients(m.data.items)));
  const drank = data.water_logs
    .filter((w) => w.data.date === date)
    .reduce((s, w) => s + w.data.amount, 0);
  const label = (k: string) =>
    ({
      breakfast: h("בוקר", "Breakfast"),
      lunch: h("צהריים", "Lunch"),
      dinner: h("ערב", "Dinner"),
      snack: h("ביניים", "Snack"),
    })[k];
  async function recordWater(amount: number) {
    try {
      await save("water_logs", { date, amount });
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    }
  }
  async function recordWeight() {
    try {
      await save(
        "weight_logs",
        { date, weight: +weight },
        data.weight_logs.find((w) => w.data.date === date),
      );
      setWeight("");
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    }
  }
  async function deleteMeal(row: HealthRow<"meals">) {
    if (!window.confirm(h("למחוק את הארוחה?", "Delete this meal?"))) return;
    try {
      await remove("meals", row);
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    }
  }
  return (
    <div className="grid gap-5">
      <ErrorText error={error} />
      <div className="health-summary"><Panel
        title={h("התזונה שלי היום", "My nutrition today")}
        action={
          <Button
            onClick={() => {
              setEditing(null);
              setCapture(false);
              setAddMenu(true);
            }}
          >
            <Plus size={30}/><span className="sr-only">{h("הוספת ארוחה", "Add meal")}</span>
          </Button>
        }
      >
        <div className="health-energy">
          <div><p className="health-eyebrow">{h("האנרגיה שלך היום", "YOUR DAILY ENERGY")}</p><p className="mt-2 text-3xl font-bold tabular-nums">{goal ? round(Math.max(0, goal.kcal-totals.kcal)) : round(totals.kcal)}</p><p className="mt-1 text-sm text-muted-foreground">{goal ? h("קלוריות נותרו ליעד", "calories to your goal") : h("קלוריות נרשמו", "calories logged")}</p><p className="mt-4 text-xs text-muted-foreground">{goal ? `${round(totals.kcal)} / ${round(goal.kcal)} kcal` : h("כל צעד קטן נחשב", "Every small step counts")}</p></div>
          <div className="health-ring"><NutrientRing value={totals.kcal} target={goal?.kcal} label={h("קלוריות מול היעד", "Calories vs goal")} color="#f4a900" trackColor="#fff3ca"/><div className="health-ring-label" aria-hidden="true"><Flame size={42} fill="#f4a900" stroke="#f4a900"/></div></div>
        </div>
        <div className="health-macros grid grid-cols-3 gap-3">
          {(
            [
              ["protein", h("חלבון", "Protein")],
              ["carbs", h("פחמימות", "Carbs")],
              ["fat", h("שומן", "Fat")],
            ] as const
          ).map(([k, label]) => (
            <div key={k} className={`health-macro macro-${k}`}>
              <span className="health-macro-icon"><NutrientRing value={totals[k]} target={goal?.[k]} label={label}/><span aria-hidden="true">{k==="protein" ? <Beef size={23}/> : k==="carbs" ? <Wheat size={23}/> : <Droplet size={23}/>}</span></span>
              <p className="mt-4 text-xl font-bold tabular-nums">{round(goal ? Math.max(0,goal[k]-totals[k]) : totals[k])}<small className="text-xs font-normal"> {h("גרם", "g")}</small></p>
              <p className="mt-1 text-xs text-muted-foreground">{label} {goal ? h("נותרו", "left") : h("נרשמו", "logged")}</p>
            </div>
          ))}
        </div>
        {!goal && (
          <p className="mt-3 text-sm text-muted-foreground">
            {h(
              "אפשר להגדיר יעד בהגדרות. המעקב עובד גם ללא יעד.",
              "Set a goal in Settings. Tracking works without one.",
            )}
          </p>
        )}
        {meals.length === 0 && (
          <p className="mt-3 text-xs text-muted-foreground">
            {h(
              "אין דיווחים ליום הזה; הסכום מתייחס לרישומים בלבד.",
              "No entries for this day; totals reflect logged food only.",
            )}
          </p>
        )}
        <details className="mt-4 text-sm">
          <summary>{h("ערכים נוספים", "More nutrients")}</summary>
          <div className="mt-2 grid grid-cols-2 gap-2">
            {(
              [
                ["fiber", h("סיבים", "Fiber")],
                ["sugar", h("סוכר", "Sugar")],
                ["saturatedFat", h("שומן רווי", "Saturated fat")],
                ["sodium", h("נתרן", "Sodium")],
              ] as const
            ).map(([k, n]) => (
              <p key={k}>
                {n}: {round(totals[k])} {k === "sodium" ? "mg" : "g"}
              </p>
            ))}
          </div>
          <p className="mt-2 text-xs text-muted-foreground">
            {h(
              "— פירושו שאין נתון מלא לכל המזונות שנרשמו.",
              "— means data is incomplete for the logged foods.",
            )}
          </p>
        </details>
      </Panel>
      </div>
      <button className="health-scan" onClick={()=>openEntry("photo")}><span><Camera size={25}/></span><span className="flex-1"><strong>{h("מצלמים. בודקים. מוסיפים.", "Snap. Review. Log.")}</strong><small>{h("צילום ארוחה או תווית עם AI", "Meal & nutrition label analysis")}</small></span><ArrowUpLeft size={19}/></button>
      <Dialog open={addMenu} onOpenChange={setAddMenu}><DialogContent className="health-app meal-actions start-0 top-auto bottom-0 translate-x-0 translate-y-0 rtl:translate-x-0" showCloseButton={false}><DialogTitle>{h("מה מוסיפים?", "What would you like to add?")}</DialogTitle><div className="meal-action-grid">
        {onWorkout&&<button className="workout-action" onClick={()=>{setAddMenu(false);onWorkout()}}><Dumbbell/>{h("רישום אימון", "Log a workout")}</button>}
        <button onClick={()=>openEntry("search")}><span className="amber"><Search/></span>{h("מאגר מזון", "Food database")}</button>
        <button onClick={()=>openEntry("saved")}><span className="pink"><Bookmark/></span>{h("שמורים", "Saved foods")}</button>
        <button onClick={()=>openEntry("photo")}><span><Camera/></span>{h("צלם ארוחה", "Photograph a meal")}</button>
        <button onClick={()=>openEntry("manual")}><span className="green"><PenLine/></span>{h("הזנה ידנית", "Manual entry")}</button>
      </div><Button variant="ghost" onClick={()=>setAddMenu(false)}>{h("סגירה", "Close")}</Button></DialogContent></Dialog>
      {editor && (
        <MealEditor
          capture={capture}
          foodMode={foodMode}
          onBrowse={()=>setCapture(false)}
          key={editing?.id ?? `new-${date}`}
          date={date}
          existing={editing}
          onClose={() => {
            setEditor(false);
            setEditing(null);
          }}
        />
      )}
      <h2 className="mt-3 text-2xl font-bold">{h("הארוחות של היום", "Your meals today")}</h2>
      {kinds.filter(kind=>meals.length===0 ? kind==="breakfast" : meals.some(m=>m.data.kind===kind)).map((kind) => (
        <Panel key={kind} title={label(kind) ?? kind}>
          {meals.filter((m) => m.data.kind === kind).length === 0 ? (
            <Empty>{h("עדיין אין ארוחה", "No meal logged yet")}</Empty>
          ) : (
            meals
              .filter((m) => m.data.kind === kind)
              .map((m) => {
                const n = mealNutrients(m.data.items);
                return (
                  <article
                    key={m.id}
                    className="mb-3 rounded-xl border p-3 last:mb-0"
                  >
                    <div className="flex items-start justify-between gap-2">
                      <div>
                        <h3 className="font-medium">
                          {m.data.name ||
                            m.data.items.map((i) => i.food.name).join(", ")}
                        </h3>
                        <p className="mt-1 text-sm text-muted-foreground">
                          {round(n.kcal)} kcal · P {round(n.protein)} / C{" "}
                          {round(n.carbs)} / F {round(n.fat)}
                        </p>
                      </div>
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => {
                          setEditing(m);
                          setEditor(true);
                        }}
                      >
                        {h("עריכה", "Edit")}
                      </Button>
                    </div>
                    <details className="mt-2 text-sm">
                      <summary>
                        {h("פריטים ופעולות", "Items & actions")}
                      </summary>
                      {m.data.items.map((i) => (
                        <p key={i.id} className="mt-2">
                          {i.food.name} · {i.quantity} {i.food.basis} ·{" "}
                          {i.food.source}
                        </p>
                      ))}
                      {m.data.imagePath && (
                        <MealImage path={m.data.imagePath} />
                      )}
                      <div className="mt-3 flex flex-wrap gap-2">
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => {
                            setEditing({ ...m, id: "", version: 0 });
                            setEditor(true);
                          }}
                        >
                          {h("העתקה לתאריך אחר", "Copy to another date")}
                        </Button>
                        <Button
                          variant="destructive"
                          size="sm"
                          onClick={() => void deleteMeal(m)}
                        >
                          {h("מחיקה", "Delete")}
                        </Button>
                      </div>
                    </details>
                  </article>
                );
              })
          )}
        </Panel>
      ))}
      <FoodLibrary />
      <Panel title={h("מים ומשקל", "Water & weight")}>
        <p className="mb-3 text-lg font-semibold">
          {drank.toLocaleString()} / {profile.waterTarget.toLocaleString()}{" "}
          {h("מ״ל", "ml")}
        </p>
        <div className="flex flex-wrap gap-2">
          {[250, 500].map((v) => (
            <Button
              key={v}
              variant="outline"
              onClick={() => void recordWater(v)}
            >
              +{v} ml
            </Button>
          ))}
        </div>
        <form
          className="mt-3 flex items-end gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            void recordWater(water);
          }}
        >
          <div className="flex-1">
            <Field
              label={h("כמות מים במ״ל", "Water amount (ml)")}
              type="number"
              min={1}
              max={5000}
              value={water}
              onChange={(e) => setWater(+e.target.value)}
            />
          </div>
          <Button type="submit">{h("הוספה", "Add")}</Button>
        </form>
        <details className="mt-3 text-sm">
          <summary>
            {h("רישומי מים ותיקונים", "Water entries & corrections")}
          </summary>
          {data.water_logs
            .filter((w) => w.data.date === date)
            .map((w) => (
              <div key={w.id} className="mt-2 flex justify-between">
                <span>{w.data.amount} ml</span>
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() =>
                    void remove("water_logs", w).catch(() => setError("failed"))
                  }
                >
                  {h("מחיקה", "Delete")}
                </Button>
              </div>
            ))}
        </details>
        <form
          className="mt-5 flex items-end gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            void recordWeight();
          }}
        >
          <div className="flex-1">
            <Field
              label={h("שקילה בק״ג", "Weight (kg)")}
              type="number"
              min={20}
              max={400}
              step="0.1"
              value={weight}
              onChange={(e) => setWeight(e.target.value)}
              placeholder={String(
                data.weight_logs.find((w) => w.data.date === date)?.data
                  .weight ?? "",
              )}
            />
          </div>
          <Button type="submit" disabled={!weight}>
            {h("שמירת שקילה", "Save weight")}
          </Button>
        </form>
        {data.weight_logs.find((w) => w.data.date === date) && (
          <p className="mt-2 text-sm text-muted-foreground">
            {h("נרשם", "Recorded")}:{" "}
            {data.weight_logs.find((w) => w.data.date === date)?.data.weight} kg
            ·{" "}
            {h(
              "עדכון יעד דורש אישור בהגדרות.",
              "Goal updates require confirmation in Settings.",
            )}
          </p>
        )}
      </Panel>
    </div>
  );
}
function MealEditor({
  onBrowse,
  foodMode,
  capture,
  date,
  existing,
  onClose,
}: {
  onBrowse: ()=>void;
  foodMode?: "search"|"saved"|"manual";
  capture?: boolean;
  date: string;
  existing: HealthRow<"meals"> | null;
  onClose: () => void;
}) {
  const h = useHealthText();
  const owner = useHealthStore((s) => s.owner),
    data = useHealthStore((s) => s.data),
    save = useHealthStore((s) => s.save);
  const [meal, setMeal] = useState<Payload<"meals">>(
    () =>
      existing?.data ?? {
        date,
        kind: "breakfast",
        name: "",
        items: [],
        imagePath: null,
      },
  );
  const [error, setError] = useState<string | null>(null),
    [busy, setBusy] = useState(false),
    [mode, setMode] = useState<"meal" | "label">("meal"),
    [description, setDescription] = useState("");
  const [photo, setPhoto] = useState<File | null>(null),
    [requestId, setRequestId] = useState(() => crypto.randomUUID()),
    [question, setQuestion] = useState("");
  const [recipeName, setRecipeName] = useState(""),
    [servings, setServings] = useState(1);
  const profile = data.health_profiles[0];
  const consent = profile?.data.aiConsent ?? false;
  async function agree() {
    try {
      await save(
        "health_profiles",
        { ...(profile?.data ?? profileSchema.parse({})), aiConsent: true },
        profile,
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    }
  }
  async function analyze() {
    if (!photo || !owner) return;
    setBusy(true);
    setError(null);
    try {
      const path = meal.imagePath ?? (await uploadMealImage(photo, owner));
      setMeal((m) => ({ ...m, imagePath: path }));
      const result = await analyzeMeal(path, requestId, mode, description);
      setMeal((m) => ({ ...m, items: result.items }));
      setQuestion(result.question);
      if (!result.items.length && !result.question)
        setQuestion(
          h(
            "לא זוהה מזון. אפשר להזין ידנית.",
            "No food identified. Enter manually.",
          ),
        );
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    } finally {
      setBusy(false);
    }
  }
  async function persist() {
    setBusy(true);
    setError(null);
    try {
      await save("meals", meal, existing?.id ? existing : undefined);
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    } finally {
      setBusy(false);
    }
  }
  async function recipe() {
    setError(null);
    try {
      if (meal.items.some((i) => i.food.basis !== "g"))
        throw new Error("recipe_grams_required");
      await save("recipes", { name: recipeName, servings, items: meal.items });
      setRecipeName("");
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    }
  }
  function itemPatch(id: string, patch: Partial<MealItem>) {
    setMeal((m) => ({
      ...m,
      items: m.items.map((i) => (i.id === id ? { ...i, ...patch } : i)),
    }));
  }
  const totals = mealNutrients(meal.items);
  return (
    <Dialog open onOpenChange={(open)=>{if(!open&&!busy)onClose()}}>
    <DialogContent className="health-app meal-composer start-0 top-auto bottom-0 translate-x-0 translate-y-0 rtl:translate-x-0" showCloseButton={false}>
    <DialogTitle className="sr-only">{h("הוספת ארוחה", "Add meal")}</DialogTitle>
    <Panel
      title={existing ? h("עריכת ארוחה", "Meal editor") : h("מה אוכלים היום?", "What’s on your plate?")}
      action={
        <Button variant="ghost" disabled={busy} onClick={onClose}>
          {h("סגירה", "Close")}
        </Button>
      }
    >
      <div className="grid gap-4">
        <ErrorText error={error} />
        <p className="text-sm text-muted-foreground">{h("מוסיפים מזון, בודקים כמויות ושומרים ביומן שלך.", "Add food, review your portions and save to your diary.")}</p>
        <details className="meal-metadata"><summary>{h("פרטי הארוחה והתאריך", "Meal details & date")}</summary>
        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          <Field
            label={h("תאריך הארוחה", "Meal date")}
            type="date"
            value={meal.date}
            onChange={(e) => setMeal((m) => ({ ...m, date: e.target.value }))}
          />
          <SelectField
            label={h("סוג ארוחה", "Meal type")}
            value={meal.kind}
            onChange={(e) =>
              setMeal((m) => ({
                ...m,
                kind: e.target.value as Payload<"meals">["kind"],
              }))
            }
          >
            {kinds.map((k, i) => (
              <option key={k} value={k}>
                {
                  [
                    h("בוקר", "Breakfast"),
                    h("צהריים", "Lunch"),
                    h("ערב", "Dinner"),
                    h("ביניים", "Snack"),
                  ][i]
                }
              </option>
            ))}
          </SelectField>
        </div>
        <Field
          label={h("שם הארוחה (אופציונלי)", "Meal name (optional)")}
          value={meal.name}
          onChange={(e) => setMeal((m) => ({ ...m, name: e.target.value }))}
        />
        </details>
        {capture && <details open className="meal-photo-entry rounded-xl border p-3">
          <summary>
            {h("צילום ארוחה או תווית עם AI", "Analyze a meal or label with AI")}
          </summary>
          <div className="mt-3 grid gap-3">
            <p className="text-sm text-muted-foreground">
              {h(
                "צילום ארוחה נותן הערכה בלבד. יש לבדוק כמויות, שמן ורטבים. צילום תווית קורא את הערכים המודפסים.",
                "Meal photos provide estimates. Check portions, oil and sauces. Label scans read printed values.",
              )}
            </p>
            {!consent ? (
              <div className="rounded-lg bg-muted p-3 text-sm">
                <p>
                  {h(
                    "התמונה תישלח ל־Google. במסלול החינמי התוכן עשוי לשמש לשיפור השירות. העלו מזון בלבד, ללא אנשים, שמות או מידע אישי. פרופיל הגוף וההיסטוריה לא נשלחים.",
                    "The image is sent to Google. Free-tier content may be used to improve its services. Upload only food, without people, names or personal information. Your body profile and history are not sent.",
                  )}
                </p>
                <Button
                  className="mt-3"
                  variant="outline"
                  onClick={() => void agree()}
                >
                  {h(
                    "הבנתי, אפשר לנתח תמונות מזון",
                    "I understand; enable food image analysis",
                  )}
                </Button>
              </div>
            ) : (
              <>
                <SelectField
                  label={h("סוג צילום", "Image type")}
                  value={mode}
                  onChange={(e) => {
                    setMode(e.target.value as "meal" | "label");
                    setRequestId(crypto.randomUUID());
                  }}
                >
                  <option value="meal">{h("ארוחה", "Meal")}</option>
                  <option value="label">
                    {h("תווית תזונתית", "Nutrition label")}
                  </option>
                </SelectField>
                <Field
                  label={h("צילום או העלאת תמונה", "Take or upload a photo")}
                  type="file"
                  accept="image/*"
                  onChange={(e) => {
                    setPhoto(e.target.files?.[0] ?? null);
                    setMeal((m) => ({ ...m, imagePath: null }));
                    setRequestId(crypto.randomUUID());
                  }}
                />
                <Field
                  label={h("הסבר על המזון או הכמות", "Food or portion details")}
                  value={description}
                  onChange={(e) => {
                    setDescription(e.target.value);
                    setRequestId(crypto.randomUUID());
                  }}
                />
                <Button
                  variant="outline"
                  disabled={busy || !photo}
                  onClick={() => void analyze()}
                >
                  {busy
                    ? h("מנתח…", "Analyzing…")
                    : h(
                        "ניתוח לטיוטה — יחליף את הפריטים בטיוטה",
                        "Analyze draft — replaces draft items",
                      )}
                </Button>
              </>
            )}
            {question && (
              <p
                role="status"
                className="rounded-lg bg-amber-500/10 p-3 text-sm"
              >
                {question}
              </p>
            )}
          </div>
        </details>}
        {capture && <Button variant="outline" onClick={onBrowse}>{h("חיפוש או הוספת מזון ידנית", "Search or add food manually")}</Button>}
        {!capture && <div className="meal-search-section"><p className="mb-3 text-sm font-semibold">{h("חיפוש מזון או מוצר", "Find a food or product")}</p>
        <FoodPicker initialMode={foodMode}
          onAdd={(item) =>
            setMeal((m) => ({ ...m, items: [...m.items, item] }))
          }
        />
        </div>}
        {meal.items.length>0 && <h3 className="mt-2 text-xl font-bold">{h("בארוחה שלך", "On your plate")}</h3>}
        {meal.items.map((i) => (
          <div key={i.id} className="meal-review-item rounded-xl border p-3">
            <div className="flex items-center justify-between gap-2">
              <h3 className="font-medium">{i.food.name}</h3>
              <Button
                size="sm"
                variant="ghost"
                onClick={() =>
                  setMeal((m) => ({
                    ...m,
                    items: m.items.filter((x) => x.id !== i.id),
                  }))
                }
              >
                {h("הסרה", "Remove")}
              </Button>
            </div>
            <div className="mt-2 grid grid-cols-2 items-end gap-3">
              <Field
                label={`${h("כמות", "Amount")} (${i.food.basis})`}
                type="number"
                min={0.1}
                max={10000}
                step="0.1"
                value={i.quantity}
                onChange={(e) => itemPatch(i.id, { quantity: +e.target.value })}
              />
              <p className="pb-2 text-sm">
                {round(scaleNutrients(i.food.per100, i.quantity).kcal)} kcal
              </p>
            </div>
            <p className="mt-2 text-xs text-muted-foreground">
              {i.food.source} {i.assumption ? `· ${i.assumption}` : ""}
            </p>
            <details className="mt-2 text-sm">
              <summary>
                {h(
                  "בדיקה ותיקון ערכים ל־100",
                  "Review / correct values per 100",
                )}
              </summary>
              <Field
                label={h("שם המזון", "Food name")}
                value={i.food.name}
                onChange={(e) =>
                  itemPatch(i.id, { food: { ...i.food, name: e.target.value } })
                }
              />
              <div className="mt-2 grid grid-cols-2 gap-2">
                {(
                  [
                    "kcal",
                    "protein",
                    "carbs",
                    "fat",
                    "fiber",
                    "sugar",
                    "saturatedFat",
                    "sodium",
                  ] as (keyof Nutrients)[]
                ).map((k) => (
                  <Field
                    key={k}
                    label={`${k} / 100 ${i.food.basis}`}
                    type="number"
                    min={0}
                    step="0.1"
                    value={i.food.per100[k] ?? ""}
                    onChange={(e) =>
                      itemPatch(i.id, {
                        food: {
                          ...i.food,
                          source: "manual",
                          per100: {
                            ...i.food.per100,
                            [k]: e.target.value === "" ? null : +e.target.value,
                          },
                        },
                      })
                    }
                  />
                ))}
              </div>
              <Button
                className="mt-2"
                size="sm"
                variant="outline"
                onClick={() =>
                  void save(
                    "personal_foods",
                    i.food,
                    data.personal_foods.find((f) => f.data.id === i.food.id),
                  ).catch(() => setError("failed"))
                }
              >
                {h("שמירה במזונות האישיים", "Save to my foods")}
              </Button>
            </details>
          </div>
        ))}
        <div className="meal-savebar"><strong>
          {round(totals.kcal)} kcal · P {round(totals.protein)} / C{" "}
          {round(totals.carbs)} / F {round(totals.fat)}
        </strong>
        <Button
          disabled={busy || !meal.items.length}
          onClick={() => void persist()}
        >
          {h("אישור והוספה ליומן", "Confirm & save to diary")}
        </Button>
        </div>
        {meal.items.length > 0 && (
          <details>
            <summary>
              {h("שמירת הפריטים כמתכון", "Save items as a recipe")}
            </summary>
            <div className="mt-3 grid gap-3">
              <Field
                label={h("שם המתכון", "Recipe name")}
                value={recipeName}
                onChange={(e) => setRecipeName(e.target.value)}
              />
              <Field
                label={h("מספר מנות", "Number of servings")}
                type="number"
                min={0.1}
                step="0.1"
                value={servings}
                onChange={(e) => setServings(+e.target.value)}
              />
              <p className="text-xs text-muted-foreground">
                {h(
                  "מרכיבי מתכון נשקלים בגרמים. לנוזלים יש להזין משקל בפועל, ללא המרת מ״ל אוטומטית.",
                  "Recipe ingredients use grams. Weigh liquids; ml are not automatically converted to grams.",
                )}
              </p>
              <Button
                variant="outline"
                disabled={!recipeName || busy}
                onClick={() => void recipe()}
              >
                {h("שמירת מתכון", "Save recipe")}
              </Button>
            </div>
          </details>
        )}
      </div>
    </Panel>
    </DialogContent>
    </Dialog>
  );
}

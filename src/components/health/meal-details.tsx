"use client";
import { displayedMealTitle } from "@/lib/health/meal-presentation";
import { Utensils, PencilLine } from "lucide-react";
import { useRef, useState } from "react";
import { useHealthStore } from "@/lib/health/store";
import { correctSavedMeal } from "@/lib/health/wellness-api";
import { useHealthText } from "@/lib/health/i18n";
import { HealthSheet } from "./health-sheet";
import { MealImage } from "./meal-image";
import { MealPortion } from "./meal-portion";
import { AiConsent, useWellnessAvailability } from "./ai-consent";
import { mealNutrients, scaleNutrients } from "@/lib/health/calculations";
import { Disclosure, ErrorText, round } from "./shared";
import { Button } from "@/components/ui/button";
export function MealDetails({
  id,
  onClose,
  onEdit,
}: {
  id: string;
  onClose: () => void;
  onEdit: () => void;
}) {
  const h = useHealthText(),
    row = useHealthStore((s) => s.data.meals.find((m) => m.id === id)),
    availability = useWellnessAvailability();
  const [text, setText] = useState(""),
    [portionId, setPortionId] = useState<string | null>(null),
    [busy, setBusy] = useState(false),
    [message, setMessage] = useState(""),
    [error, setError] = useState<string | null>(null);
  const lock = useRef(false),
    attempt = useRef<{ text: string; version: number; id: string } | null>(
      null,
    );
  if (!row) return null;
  const meal = row,
    totals = mealNutrients(row.data.items),
    hasAiFood = row.data.items.some((i) => ["ai", "usda"].includes(i.food.source));
  async function correct() {
    if (lock.current || !text.trim() || !availability.ready) return;
    lock.current = true;
    setBusy(true);
    setMessage("");
    setError(null);
    if (
      attempt.current?.text !== text ||
      attempt.current.version !== meal.version
    )
      attempt.current = {
        text,
        version: meal.version,
        id: crypto.randomUUID(),
      };
    try {
      await correctSavedMeal(meal, text, attempt.current.id);
      setText("");
      setMessage(h("הארוחה עודכנה", "Meal updated"));
    } catch (e) {
      const code = e instanceof Error ? e.message : "failed";
      setError(code === "version_conflict" ? "sync_required" : code);
    } finally {
      lock.current = false;
      setBusy(false);
    }
  }
  return (
    <HealthSheet
      title={displayedMealTitle(row.data, h("הארוחה שלי", "My meal"))}
      onClose={onClose}
    >
      <div className="grid gap-5">
        {hasAiFood && (
          <section className="health-recognition-correction grid gap-3" aria-label={h("תיקון זיהוי במלל", "Correct recognition with text")}>
            <h3 className="font-semibold">{h("תיקון הזיהוי במילים שלך", "Correct the recognition in your own words")}</h3>
            <AiConsent />
            <label>
              {h("מה צריך לתקן?", "What should change?")}
              <textarea
                className="health-meal-correction mt-2 w-full"
                disabled={busy}
                value={text}
                onChange={(e) => setText(e.target.value)}
                maxLength={2000}
                placeholder={h(
                  "למשל: זה דג ולא חזה עוף",
                  "For example: this is fish, not chicken breast",
                )}
              />
            </label>
            <Button
              className="health-primary-action"
              disabled={busy || !!portionId || !availability.ready || !text.trim()}
              onClick={() => void correct()}
            >
              {busy
                ? h("מעדכן…", "Updating…")
                : h("עדכון הארוחה", "Update meal")}
            </Button>
            <ErrorText error={error} />
            {message && <p role="status">{message}</p>}
          </section>
        )}
        {row.data.imagePath && <MealImage path={row.data.imagePath} preview />}
        {!hasAiFood && (row.data.imagePath || row.data.aiEstimate) && <p className="text-sm text-muted-foreground">{h("הערכים בארוחה נשמרו ממוצר או הוזנו ידנית. אפשר לעדכן אותם בעריכה ידנית.", "This meal uses product or manually entered values. Use manual editing to update them.")}</p>}

        <div className="health-meal-detail-total">
          <strong>
            {round(totals.kcal)} <small>kcal</small>
          </strong>
          <p>
            {h("חלבון", "Protein")} {round(totals.protein)}g ·{" "}
            {h("פחמימות", "Carbs")} {round(totals.carbs)}g · {h("שומן", "Fat")}{" "}
            {round(totals.fat)}g
          </p>
        </div>
        <ul
          className="health-ingredient-list"
          aria-label={h("מרכיבי הארוחה", "Meal ingredients")}
        >
          {row.data.items.map((i) => {
            const nutrients = scaleNutrients(i.food.per100, i.quantity);
            return (
              <li key={i.id}>
                <span className="health-ingredient-icon" aria-hidden="true">
                  <Utensils size={19} />
                </span>
                <button type="button" disabled={busy} className="health-ingredient-copy text-start" aria-label={`${h("עדכון כמות", "Update amount")}: ${i.food.name}`} onClick={() => setPortionId(i.id)}>
                  <strong>{i.food.name}</strong>
                  <span className="flex items-center gap-2">
                    {round(i.quantity)}{" "}
                    {i.food.basis === "g" ? h("גרם", "g") : h("מ״ל", "ml")}
                    <PencilLine size={13} aria-hidden="true" />
                  </span>
                </button>
                <span className="health-ingredient-energy">
                  <strong>{round(nutrients.kcal)}</strong>
                  <small>{h("קל׳", "kcal")}</small>
                </span>
              </li>
            );
          })}
        </ul>
        {portionId && row.data.items.find((i) => i.id === portionId) && <MealPortion key={`${portionId}:${row.version}`} meal={row} item={row.data.items.find((i) => i.id === portionId)!} onDone={() => setPortionId(null)} />}
        {row.data.items.some((i) => i.quantityRange || i.assumption) && (
          <Disclosure title={h("על ההערכה", "About this estimate")}>
            {row.data.items
              .filter((i) => i.quantityRange || i.assumption)
              .map((i) => (
                <p key={i.id} className="text-sm">
                  <strong>{i.food.name}</strong>
                  {i.quantityRange
                    ? ` · ${round(i.quantityRange.low)}–${round(i.quantityRange.high)} ${i.food.basis}`
                    : ""}
                  {i.assumption ? ` · ${i.assumption}` : ""}
                </p>
              ))}
          </Disclosure>
        )}
        <Button variant="outline" disabled={busy || !!portionId} onClick={onEdit}>
          {h("עריכה ידנית", "Edit manually")}
        </Button>
      </div>
    </HealthSheet>
  );
}

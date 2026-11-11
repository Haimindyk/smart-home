"use client";
import { displayedMealTitle } from "@/lib/health/meal-presentation";
import { Utensils } from "lucide-react";
import { useRef, useState } from "react";
import { useHealthStore } from "@/lib/health/store";
import { correctSavedMeal } from "@/lib/health/wellness-api";
import { useHealthText } from "@/lib/health/i18n";
import { HealthSheet } from "./health-sheet";
import { AiConsent, useWellnessAvailability } from "./ai-consent";
import { mealNutrients, scaleNutrients } from "@/lib/health/calculations";
import { Disclosure, round } from "./shared";
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
    [busy, setBusy] = useState(false),
    [message, setMessage] = useState("");
  const lock = useRef(false),
    attempt = useRef<{ text: string; version: number; id: string } | null>(
      null,
    );
  if (!row) return null;
  const meal = row,
    totals = mealNutrients(row.data.items);
  async function correct() {
    if (lock.current || !text.trim() || !availability.ready) return;
    lock.current = true;
    setBusy(true);
    setMessage("");
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
    } catch {
      setMessage(
        h(
          "לא ניתן לעדכן כרגע. סנכרנו את היומן ונסו שוב.",
          "Could not update. Sync the diary and retry.",
        ),
      );
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
                <div className="health-ingredient-copy">
                  <strong>{i.food.name}</strong>
                  <span>
                    {round(i.quantity)}{" "}
                    {i.food.basis === "g" ? h("גרם", "g") : h("מ״ל", "ml")}
                  </span>
                </div>
                <span className="health-ingredient-energy">
                  <strong>{round(nutrients.kcal)}</strong>
                  <small>{h("קל׳", "kcal")}</small>
                </span>
              </li>
            );
          })}
        </ul>
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
        {row.data.items.some((i) => ["ai", "usda"].includes(i.food.source)) && (
          <>
            <p>
              {h(
                "הערכת AI · אפשר לתקן או להוסיף מרכיב",
                "AI estimate · Correct or add an ingredient",
              )}
            </p>
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
                  "למשל: יש גם מיונז 15 גרם",
                  "For example: also add 15 g of mayonnaise",
                )}
              />
            </label>
            <Button
              className="health-primary-action"
              disabled={busy || !availability.ready || !text.trim()}
              onClick={() => void correct()}
            >
              {busy
                ? h("מעדכן…", "Updating…")
                : h("עדכון הארוחה", "Update meal")}
            </Button>
            <p role="status">{message}</p>
          </>
        )}
        <Button variant="outline" disabled={busy} onClick={onEdit}>
          {h("עריכה ידנית", "Edit manually")}
        </Button>
      </div>
    </HealthSheet>
  );
}

"use client";
import { useRef, useState } from "react";
import { useHealthStore } from "@/lib/health/store";
import { correctSavedMeal } from "@/lib/health/wellness-api";
import { useHealthText } from "@/lib/health/i18n";
import { HealthSheet } from "./health-sheet";
import { AiConsent, useWellnessAvailability } from "./ai-consent";
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
  const meal = row;
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
      title={row.data.name || h("הארוחה שלי", "My meal")}
      onClose={onClose}
    >
      <div className="grid gap-5">
        {row.data.items.map((i) => (
          <div key={i.id}>
            <strong>{i.food.name}</strong>
            <p>
              {i.quantity} {i.food.basis}
            </p>
          </div>
        ))}
        {row.data.items.some((i) => ["ai", "usda"].includes(i.food.source)) && (
          <>
            <p>
              {h(
                "הערכת AI · אפשר לתקן זיהוי וכמות",
                "AI estimate · Correct food and portions",
              )}
            </p>
            <AiConsent />
            <label>
              {h("מה צריך לתקן?", "What should change?")}
              <textarea
                className="mt-2 w-full"
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

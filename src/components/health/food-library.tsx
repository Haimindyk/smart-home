"use client";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { useHealthStore } from "@/lib/health/store";
import { useHealthText } from "@/lib/health/i18n";
import type { HealthRow } from "@/lib/health/model";
import { Field, Panel, ErrorText, Empty } from "./shared";
export function FoodLibrary() {
  const h = useHealthText(),
    data = useHealthStore((s) => s.data),
    save = useHealthStore((s) => s.save),
    remove = useHealthStore((s) => s.remove);
  const [recipe, setRecipe] = useState<HealthRow<"recipes"> | null>(null),
    [error, setError] = useState<string | null>(null);
  async function saveRecipe() {
    if (!recipe) return;
    try {
      if (recipe.data.items.some((i) => i.food.basis !== "g"))
        throw new Error("recipe_grams_required");
      await save("recipes", recipe.data, recipe);
      setRecipe(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    }
  }
  async function erase(table: "recipes" | "personal_foods", id: string) {
    if (
      !window.confirm(
        h(
          "למחוק מהספרייה האישית? הארוחות שכבר נרשמו לא ישתנו.",
          "Delete from your library? Previously logged meals will stay unchanged.",
        ),
      )
    )
      return;
    try {
      if (table === "recipes") {
        const row = data.recipes.find((r) => r.id === id);
        if (row) await remove(table, row);
      } else {
        const row = data.personal_foods.find((r) => r.id === id);
        if (row) await remove(table, row);
      }
    } catch {
      setError("failed");
    }
  }
  return (
    <Panel title={h("הספרייה שלי", "My food library")}>
      <ErrorText error={error} />
      <details>
        <summary>{h("מזונות אישיים ומועדפים", "My foods & favorites")}</summary>
        <div className="mt-3 grid gap-2">
          {!data.personal_foods.length && (
            <Empty>
              {h("מזונות שתשמרו יופיעו כאן", "Saved foods appear here")}
            </Empty>
          )}
          {data.personal_foods.map((f) => (
            <div
              key={f.id}
              className="flex items-center justify-between gap-2 text-sm"
            >
              <span>{f.data.name}</span>
              <Button
                size="sm"
                variant="ghost"
                onClick={() => void erase("personal_foods", f.id)}
              >
                {h("הסרה", "Remove")}
              </Button>
            </div>
          ))}
        </div>
      </details>
      <details className="mt-4">
        <summary>{h("המתכונים שלי", "My recipes")}</summary>
        <div className="mt-3 grid gap-2">
          {data.recipes.map((r) => (
            <div
              key={r.id}
              className="flex flex-wrap items-center gap-2 text-sm"
            >
              <span className="me-auto">
                {r.data.name} · {r.data.servings} {h("מנות", "servings")}
              </span>
              <Button
                size="sm"
                variant="outline"
                onClick={() => setRecipe(structuredClone(r))}
              >
                {h("עריכה", "Edit")}
              </Button>
              <Button
                size="sm"
                variant="ghost"
                onClick={() => void erase("recipes", r.id)}
              >
                {h("מחיקה", "Delete")}
              </Button>
            </div>
          ))}
        </div>
      </details>
      {recipe && (
        <div className="mt-4 grid gap-3 rounded-xl border p-3">
          <Field
            label={h("שם המתכון", "Recipe name")}
            value={recipe.data.name}
            onChange={(e) =>
              setRecipe((r) =>
                r ? { ...r, data: { ...r.data, name: e.target.value } } : r,
              )
            }
          />
          <Field
            label={h("מספר מנות", "Servings")}
            type="number"
            min={0.1}
            step="0.1"
            value={recipe.data.servings}
            onChange={(e) =>
              setRecipe((r) =>
                r
                  ? { ...r, data: { ...r.data, servings: +e.target.value } }
                  : r,
              )
            }
          />
          {recipe.data.items.map((i) => (
            <Field
              key={i.id}
              label={`${i.food.name} (g)`}
              type="number"
              min={0.1}
              step="0.1"
              value={i.quantity}
              onChange={(e) =>
                setRecipe((r) =>
                  r
                    ? {
                        ...r,
                        data: {
                          ...r.data,
                          items: r.data.items.map((x) =>
                            x.id === i.id
                              ? { ...x, quantity: +e.target.value }
                              : x,
                          ),
                        },
                      }
                    : r,
                )
              }
            />
          ))}
          <div className="flex gap-2">
            <Button onClick={() => void saveRecipe()}>
              {h("שמירת מתכון", "Save recipe")}
            </Button>
            <Button variant="ghost" onClick={() => setRecipe(null)}>
              {h("ביטול", "Cancel")}
            </Button>
          </div>
        </div>
      )}
    </Panel>
  );
}

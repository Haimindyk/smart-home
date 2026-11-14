"use client";
import { useRef, useState } from "react";
import { Bookmark, Plus, Utensils } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useHealthStore } from "@/lib/health/store";
import { useHealthText } from "@/lib/health/i18n";
import { displayedMealTitle, mealTitle } from "@/lib/health/meal-presentation";
import { mealNutrients } from "@/lib/health/calculations";
import { repeatedMealData, saveRepeatedMeal, saveMealFavorite } from "@/lib/health/meal-editing";
import type { HealthRow } from "@/lib/health/model";
import { HealthSheet } from "./health-sheet";
import { ChoiceTabs, Empty, ErrorText, Field, round } from "./shared";

export function RecentMeals({ date, onClose }: { date: string; onClose: () => void }) {
  const h = useHealthText();
  const owner = useHealthStore((s) => s.owner), meals = useHealthStore((s) => s.data.meals);
  const [query, setQuery] = useState(""), [busy, setBusy] = useState(false), [error, setError] = useState<string | null>(null);
  const [mode, setMode] = useState("recent");
  const lock = useRef(false);
  const attempt = useRef<{ source: HealthRow<"meals">; data: ReturnType<typeof repeatedMealData>; id: string } | null>(null);
  const matches = meals.filter((m) => m.owner_user_id === owner && !m.deleted_at && (mode !== "favorites" || m.data.favorite) &&
    `${m.data.name} ${m.data.items.map((i) => i.food.name).join(" ")}`.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()))
    .toSorted((a, b) => b.data.date.localeCompare(a.data.date) || (b.created_at ?? "").localeCompare(a.created_at ?? "") || b.id.localeCompare(a.id));
  async function add(row: HealthRow<"meals">) {
    if (lock.current) return;
    lock.current = true; setBusy(true); setError(null);
    try {
      if (!attempt.current || attempt.current.source.id !== row.id || attempt.current.source.version !== row.version)
        attempt.current = { source: row, data: repeatedMealData(row, date), id: crypto.randomUUID() };
      await saveRepeatedMeal(attempt.current.source, attempt.current.data, attempt.current.id);
      onClose();
    } catch (e) {
      const code = e instanceof Error ? e.message : "failed";
      setError(code === "version_conflict" ? "meal_changed" : code);
    } finally { lock.current = false; setBusy(false); }
  }
  async function favorite(row: HealthRow<"meals">) {
    if (lock.current) return;
    lock.current = true; setBusy(true); setError(null);
    try { await saveMealFavorite(row, !row.data.favorite); }
    catch (e) { const code = e instanceof Error ? e.message : "failed"; setError(code === "version_conflict" ? "meal_changed" : code); }
    finally { lock.current = false; setBusy(false); }
  }
  return <HealthSheet title={h("ארוחות קודמות", "Previous meals")} onClose={() => { if (!busy) onClose(); }}>
    <div className="grid gap-4">
      <p className="text-sm text-muted-foreground">{h("אותה ארוחה, באותן כמויות.", "Same meal, same portions.")}</p>
      <ChoiceTabs label={h("הצגת ארוחות", "Show meals")} value={mode} onChange={setMode} options={[{value:"recent", label:h("אחרונות", "Recent")}, {value:"favorites", label:h("מועדפות", "Favorites")}]}/>
      <Field label={h("חיפוש ארוחה", "Search meals")} value={query} onChange={(e) => setQuery(e.target.value)} disabled={busy} />
      <ErrorText error={error}/>
      {matches.length === 0 && <Empty>{mode === "favorites" && !query.trim() ? h("סמנו ארוחה בסימנייה כדי לשמור אותה כאן", "Bookmark a meal to find it here") : h("לא נמצאו ארוחות קודמות", "No previous meals found")}</Empty>}
      <div className="grid gap-3">
        {matches.slice(0, 30).map((row) => {
          const title = displayedMealTitle(row.data, mealTitle(row.data.items) || h("הארוחה שלי", "My meal"));
          return <article className="flex items-center gap-3 rounded-2xl border p-4" key={row.id}>
            <Utensils className="shrink-0 text-muted-foreground" size={20} aria-hidden="true"/>
            <div className="min-w-0 flex-1"><h3 className="break-words font-semibold">{title}</h3>
              <p className="mt-1 text-xs text-muted-foreground">{new Intl.DateTimeFormat(h("he-IL", "en-GB"), { day: "numeric", month: "short" }).format(new Date(`${row.data.date}T12:00:00`))} · {round(mealNutrients(row.data.items).kcal)} kcal</p>
              <p className="mt-1 text-xs text-muted-foreground break-words">{row.data.items.slice(0, 3).map((i) => `${i.food.name} · ${i.quantity} ${i.food.basis === "ml" ? h("מ״ל", "ml") : h("גרם", "g")}`).join(" · ")}{row.data.items.length > 3 ? h(" ועוד", " and more") : ""}</p>
            </div>
            <div className="grid shrink-0 gap-2">
              <Button size="icon" variant="ghost" disabled={busy} aria-pressed={!!row.data.favorite} aria-label={`${row.data.favorite ? h("הסרה מהמועדפות", "Remove from favorites") : h("שמירה במועדפות", "Save to favorites")}: ${title}`} onClick={() => void favorite(row)}><Bookmark size={18} fill={row.data.favorite ? "currentColor" : "none"}/></Button>
              <Button size="icon" variant="outline" disabled={busy} aria-label={`${h("הוספה שוב", "Add again")}: ${title}`} onClick={() => void add(row)}><Plus size={20}/></Button>
            </div>
          </article>;
        })}
      </div>
    </div>
  </HealthSheet>;
}

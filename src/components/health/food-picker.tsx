"use client";
import { useState } from "react";
import { Search, ScanBarcode, PenLine } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useHealthStore } from "@/lib/health/store";
import {
  emptyNutrients,
  foodSchema,
  type Food,
  type MealItem,
} from "@/lib/health/model";
import { mealNutrients, scaleNutrients } from "@/lib/health/calculations";
import { lookupFood } from "@/lib/health/api";
import { useHealthText } from "@/lib/health/i18n";
import { BarcodeCamera } from "./barcode-camera";
import { Field, ErrorText, SelectField } from "./shared";
const roundValue = (v: number) => Math.round(v * 10) / 10;
export function FoodPicker({ onAdd, initialMode }: { onAdd: (item: MealItem) => void; initialMode?: "search"|"saved"|"manual" }) {
  const h = useHealthText();
  const data = useHealthStore((s) => s.data);
  const [lookupMode,setLookupMode]=useState<"search"|"barcode">("search");
  const [query, setQuery] = useState(""),
    [barcode, setBarcode] = useState(""),
    [camera, setCamera] = useState(false);
  const [results, setResults] = useState<Food[]>([]),
    [busy, setBusy] = useState(false),
    [error, setError] = useState<string | null>(null),
    [missing, setMissing] = useState("");
  const [manual, setManual] = useState(initialMode === "manual"),
    [food, setFood] = useState<Food>(() => ({
      id: crypto.randomUUID(),
      name: "",
      basis: "g",
      source: "manual",
      per100: emptyNutrients(),
    }));
  const [quantity, setQuantity] = useState(100),
    [favorite, setFavorite] = useState(true);
  async function search(code?: string) {
    setSavedOnly(false);
    setBusy(true);
    setError(null);
    setMissing("");
    try {
      const r = await lookupFood(query, code);
      setResults(r.foods);
      if (r.needsLabel)
        setMissing(r.name ?? h("המוצר לא נמצא", "Product not found"));
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    } finally {
      setBusy(false);
    }
  }
  async function addManual() {
    try {
      const parsed = foodSchema.parse({
        ...food,
        barcode: barcode || undefined,
      });
      if (quantity <= 0) throw new Error("invalid_input");
      if (favorite)
        await useHealthStore.getState().save("personal_foods", parsed);
      onAdd({ id: crypto.randomUUID(), food: parsed, quantity });
      setManual(false);
      setFood({
        id: crypto.randomUUID(),
        name: "",
        basis: "g",
        source: "manual",
        per100: emptyNutrients(),
      });
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    }
  }
  const recent = Array.from(
    new Map(
      data.meals
        .flatMap((m) => m.data.items)
        .reverse()
        .map((i) => [i.food.id, i.food]),
    ).values(),
  ).slice(0, 10);
  const [savedOnly,setSavedOnly]=useState(initialMode === "saved");
  const all = [
    ...data.personal_foods.map((f) => f.data),
    ...(savedOnly ? [] : recent),
    ...(savedOnly ? [] : results),
  ];
  const unique = Array.from(new Map(all.map((f) => [f.id, f])).values()).filter(
    (f) =>
      !query ||
      results.some((r) => r.id === f.id) ||
      f.name.toLowerCase().includes(query.toLowerCase()) ||
      f.nameEn?.toLowerCase().includes(query.toLowerCase()),
  );
  return (
    <div className="food-picker grid gap-4">
      <h3 className="font-medium">{h("הוספת מזון", "Add food")}</h3>
      <div className="food-methods">
        <button type="button" aria-pressed={!manual&&lookupMode==="search"} onClick={()=>{setManual(false);setLookupMode("search");setCamera(false)}}><Search size={19}/>{h("מאגר ומועדפים", "Foods & favorites")}</button>
        <button type="button" aria-pressed={!manual&&lookupMode==="barcode"} onClick={()=>{setManual(false);setLookupMode("barcode")}}><ScanBarcode size={19}/>{h("ברקוד", "Barcode")}</button>
        <button type="button" aria-pressed={manual} aria-label={h("מזון חדש / הזנה ידנית", "New food / manual entry")} onClick={()=>{setManual(true);setCamera(false)}}><PenLine size={19}/>{h("ידני", "Manual")}</button>
      </div>
      <ErrorText error={error} />
      {!manual && <div className="flex gap-2"><Button variant={savedOnly?"outline":"default"} onClick={()=>setSavedOnly(false)}>{h("אחרונים", "Recent")}</Button><Button variant={savedOnly?"default":"outline"} onClick={()=>setSavedOnly(true)}>{h("שמורים", "Saved")}</Button></div>}
      {!manual && lookupMode==="search" && <form
        className="flex items-end gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          void search();
        }}
      >
        <div className="flex-1">
          <Field
            label={h("חיפוש במזונות ובמועדפים", "Search foods & favorites")}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
        <Button
          type="submit"
          variant="outline"
          disabled={busy || query.trim().length < 2}
        >
          {h("חיפוש", "Search")}
        </Button>
      </form>}
      {!manual && lookupMode==="barcode" && <form
        className="flex items-end gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          void search(barcode);
        }}
      >
        <div className="flex-1">
          <Field
            label={h("ברקוד", "Barcode")}
            inputMode="numeric"
            value={barcode}
            onChange={(e) => setBarcode(e.target.value.replace(/\D/g, ""))}
          />
        </div>
        <Button
          type="submit"
          variant="outline"
          disabled={busy || !/^\d{8,14}$/.test(barcode)}
        >
          {h("איתור", "Look up")}
        </Button>
        <Button
          type="button"
          variant="outline"
          className="food-barcode-launch"
          onClick={() => setCamera((v) => !v)}
        >
          <ScanBarcode size={28}/>{h("פתח סורק ברקוד", "Open barcode scanner")}
        </Button>
      </form>}
      {camera && !manual && lookupMode==="barcode" && (
        <BarcodeCamera
          onCode={(code) => {
            setBarcode(code);
            setCamera(false);
            void search(code);
          }}
        />
      )}
      {missing && (
        <p role="status" className="text-sm text-muted-foreground">
          {missing} —{" "}
          {h(
            "אין ערכים מלאים. צלמו תווית או הזינו ידנית.",
            "No complete nutrition data. Scan a label or enter manually.",
          )}
        </p>
      )}
      <div className={`max-h-56 overflow-y-auto ${manual ? "hidden" : ""}`}>
        {unique.map((f) => (
          <button
            type="button"
            key={f.id}
            onClick={() =>
              onAdd({
                id: crypto.randomUUID(),
                food: f,
                quantity: f.servingSize ?? 100,
              })
            }
            className="food-result flex w-full items-center justify-between gap-3 text-start text-sm hover:bg-accent"
          >
            <span>
              {f.name}
              <span className="block text-xs text-muted-foreground">
                {Math.round(f.per100.kcal)} kcal / 100 {f.basis} · P {roundValue(f.per100.protein)} / C {roundValue(f.per100.carbs)} / F {roundValue(f.per100.fat)}
              </span>
            </span>
            <span aria-hidden className="food-result-add">＋</span>
          </button>
        ))}
      </div>
      {!manual && data.recipes.length > 0 && (
        <details>
          <summary className="text-sm">
            {h("המתכונים שלי", "My recipes")}
          </summary>
          {data.recipes.map((r) => {
            const nutrition = mealNutrients(r.data.items);
            const total = r.data.items.reduce((s, i) => s + i.quantity, 0);
            const recipe: Food = {
              id: r.id,
              name: r.data.name,
              basis: "g",
              source: "recipe",
              servingSize: total / r.data.servings,
              per100: scaleNutrients(nutrition, 10000 / total),
            };
            return (
              <button
                type="button"
                className="block w-full rounded-lg p-2 text-start text-sm hover:bg-accent"
                key={r.id}
                onClick={() =>
                  onAdd({
                    id: crypto.randomUUID(),
                    food: recipe,
                    quantity: recipe.servingSize!,
                  })
                }
              >
                {r.data.name} · {h("מנה", "serving")}
              </button>
            );
          })}
        </details>
      )}
      {manual && (
        <div className="grid gap-3 border-t pt-3">
          <Field
            label={h("שם מזון", "Food name")}
            value={food.name}
            onChange={(e) => setFood((f) => ({ ...f, name: e.target.value }))}
          />
          <SelectField
            label={h("הערכים הם ל־100", "Values per 100")}
            value={food.basis}
            onChange={(e) =>
              setFood((f) => ({ ...f, basis: e.target.value as "g" | "ml" }))
            }
          >
            <option value="g">{h("גרם", "grams")}</option>
            <option value="ml">{h("מ״ל", "ml")}</option>
          </SelectField>
          <div className="grid grid-cols-2 gap-3">
            {(
              [
                ["kcal", h("קלוריות", "Calories")],
                ["protein", h("חלבון (ג׳)", "Protein (g)")],
                ["carbs", h("פחמימות (ג׳)", "Carbs (g)")],
                ["fat", h("שומן (ג׳)", "Fat (g)")],
                ["fiber", h("סיבים (ג׳)", "Fiber (g)")],
                ["sugar", h("סוכר (ג׳)", "Sugar (g)")],
                ["saturatedFat", h("שומן רווי (ג׳)", "Saturated fat (g)")],
                ["sodium", h("נתרן (מ״ג)", "Sodium (mg)")],
              ] as const
            ).map(([key, label]) => (
              <Field
                key={key}
                label={label}
                type="number"
                min={0}
                step="0.1"
                value={food.per100[key] ?? ""}
                onChange={(e) =>
                  setFood((f) => ({
                    ...f,
                    per100: {
                      ...f.per100,
                      [key]: e.target.value === "" ? null : +e.target.value,
                    },
                  }))
                }
              />
            ))}
            <Field
              label={h("כמות שנאכלה", "Amount eaten")}
              type="number"
              min={0.1}
              step="0.1"
              value={quantity}
              onChange={(e) => setQuantity(+e.target.value)}
            />
          </div>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={favorite}
              onChange={(e) => setFavorite(e.target.checked)}
            />
            {h("שמירה במזונות האישיים", "Save to my foods")}
          </label>
          <Button type="button" onClick={() => void addManual()}>
            {h("הוספת מזון", "Add food")}
          </Button>
        </div>
      )}
      <details className="text-xs text-muted-foreground"><summary>{h("מקורות המידע", "Data sources")}</summary><p className="text-xs text-muted-foreground">
        {h(
          "מקורות: USDA FoodData Central (CC0), Open Food Facts (ODbL), ותוויות שאישרת. הכיסוי למוצרים ישראליים אינו מלא.",
          "Sources: USDA FoodData Central (CC0), Open Food Facts (ODbL), and labels you confirm. Israeli product coverage is incomplete.",
        )}
      </p></details>
    </div>
  );
}

"use client";
import { useRef, useState } from "react";
import { Search, ScanBarcode, PenLine, ChevronRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useHealthStore } from "@/lib/health/store";
import {
  emptyNutrients,
  foodSchema,
  mealItemSchema,
  type Food,
  type MealItem,
} from "@/lib/health/model";
import { mealNutrients, scaleNutrients } from "@/lib/health/calculations";
import { lookupFood } from "@/lib/health/api";
import { useHealthText } from "@/lib/health/i18n";
import { BarcodeCamera } from "./barcode-camera";
import { defaultProductAmount, productAmount, productAmountItem } from "@/lib/health/product-amount";
import { ProductAmountInput } from "./product-amount";
import { Field, ErrorText, SelectField, ChoiceTabs, Disclosure, Empty } from "./shared";
const roundValue = (v: number) => Math.round(v * 10) / 10;
export function FoodPicker({ onAdd, initialMode, showHeading = true }: { onAdd: (item: MealItem) => void; initialMode?: "search"|"saved"|"manual"; showHeading?: boolean }) {
  const h = useHealthText();
  const data = useHealthStore((s) => s.data);
  const [lookupMode,setLookupMode]=useState<"search"|"barcode">("search");
  const [query, setQuery] = useState(""),
    [barcode, setBarcode] = useState(""),
    [camera, setCamera] = useState(false);
  const [results, setResults] = useState<Food[]>([]),
    [selected, setSelected] = useState<Food | null>(null),
    [selection, setSelection] = useState(defaultProductAmount),
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
  const manualLock = useRef(false);
  async function search(code?: string) {
    if (code !== undefined && !/^\d{8,14}$/.test(code)) return;
    if (code === undefined && (savedOnly || query.trim().length < 2)) return;
    setSelected(null);
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
    if (manualLock.current) return;
    manualLock.current=true;setBusy(true);setError(null);
    try {
      const parsed = foodSchema.parse({
        ...food,
        barcode: barcode || undefined,
      });
      const item = mealItemSchema.parse({ id: crypto.randomUUID(), food: parsed, quantity });
      if (favorite)
        await useHealthStore.getState().save("personal_foods", parsed);
      onAdd(item);
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
    } finally { manualLock.current=false;setBusy(false); }
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
  const all = lookupMode === "barcode" ? results : [
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
  let validSelection = false;
  try { if (selected) { productAmount(selected, selection); validSelection = true; } } catch { /* Incomplete unit size. */ }
  return (
    <div className="food-picker grid gap-4">
      {showHeading && <h3 className="font-medium">{h("הוספת מזון", "Add food")}</h3>}
      {(manual || lookupMode === "barcode") && <Button className="food-search-back" type="button" variant="ghost" disabled={busy} onClick={()=>{setManual(false);setLookupMode("search");setCamera(false);setSelected(null)}}><ChevronRight size={18}/>{h("חזרה לחיפוש מזון", "Back to food search")}</Button>}
      <ErrorText error={error} />
      {!manual && lookupMode==="search" && <form
        className="food-search-form flex items-end gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          void search();
        }}
      >
        <div className="flex-1">
          <Field
            label={h("שם מזון או מוצר", "Food or product name")}
            placeholder={h("חיפוש…", "Search…")}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
        <Button
          type="submit"
          variant="outline"
          className="food-search-submit"
          aria-label={h("חיפוש", "Search")}
          disabled={busy || query.trim().length < 2}
        >
          <Search size={20}/>
        </Button>
        <Button type="button" className="food-search-barcode" disabled={busy} aria-label={h("ברקוד", "Barcode")} onClick={()=>{setLookupMode("barcode");setSelected(null);setCamera(false);setResults([]);setMissing("");setError(null)}}><ScanBarcode size={23}/></Button>
      </form>}
      {!manual && lookupMode === "search" && <ChoiceTabs label={h("הצגת מזונות", "Show foods")} value={savedOnly?"saved":"recent"} onChange={next=>{setSavedOnly(next==="saved");setMissing("");setError(null);setSelected(null)}} options={[{value:"recent",label:h("אחרונים", "Recent")},{value:"saved",label:h("שמורים", "Saved")}]}/>}
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
            "אין ערכים מלאים. הזינו את הערכים המודפסים מהאריזה.",
            "No complete nutrition data. Enter the printed package values.",
          )}
        </p>
      )}
      {selected && !manual && <div className="product-result grid gap-3">
        <strong>{selected.name}</strong>
        <ProductAmountInput food={selected} basis={selected.basis} value={selection} onChange={setSelection} />
        <div className="flex gap-2">
          <Button disabled={!validSelection} onClick={() => {
            if (!selected || !validSelection) return;
            onAdd(productAmountItem(selected, selection));
            setSelected(null);
          }}>{h("הוספת מזון", "Add food")}</Button>
          <Button variant="ghost" onClick={() => setSelected(null)}>{h("ביטול", "Cancel")}</Button>
        </div>
      </div>}
      {!manual && !selected && busy && <p role="status" className="text-sm text-muted-foreground">{h("מחפש מזונות…", "Searching foods…")}</p>}
      {!manual && !selected && !busy && unique.length===0 && <Empty>{savedOnly && lookupMode === "search" ? h("עוד אין מזונות שמורים שמתאימים לחיפוש", "No saved foods match yet") : lookupMode === "barcode" ? h("סרקו או הזינו את המספר שעל האריזה", "Scan or enter the number on the package") : query.trim() ? h("לא נמצאו מזונות. אפשר להוסיף ידנית.", "No foods found. You can add one manually.") : h("מזונות שהוספתם ליומן יופיעו כאן", "Foods you log will appear here")}</Empty>}
      <div className={`food-results ${manual || selected ? "hidden" : ""}`}>
        {unique.map((f) => (
          <button
            type="button"
            key={f.id}
            onClick={() => {
              setSelected(f);
              setSelection(f.unitWeight ? { mode: "units", quantity: "1", unitAmount: "" } : { mode: "amount", quantity: String(f.servingSize ?? 100), unitAmount: "" });
            }}
            className="food-result flex w-full items-center justify-between gap-3 text-start text-sm hover:bg-accent"
          >
            <span>
              {f.name}
              <span className="block text-xs text-muted-foreground">
                {Math.round(f.per100.kcal)} {h("קל׳", "kcal")} / 100 {f.basis === "ml" ? h("מ״ל", "ml") : h("גרם", "g")} · {h("חלבון", "P")} {roundValue(f.per100.protein)} / {h("פחמימות", "C")} {roundValue(f.per100.carbs)} / {h("שומן", "F")} {roundValue(f.per100.fat)}
                {f.unitWeight && <span className="block">{f.unitWeight.low}–{f.unitWeight.high} {f.basis} · {h("ליחידה", "per unit")}</span>}
              </span>
            </span>
            <span aria-hidden className="food-result-add">＋</span>
          </button>
        ))}
      </div>
      {!manual && lookupMode === "search" && data.recipes.length > 0 && (
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
          <Disclosure title={h("ערכים נוספים", "More nutrients")}><div className="grid grid-cols-2 gap-3">{([["fiber",h("סיבים (ג׳)","Fiber (g)")],["sugar",h("סוכר (ג׳)","Sugar (g)")],["saturatedFat",h("שומן רווי (ג׳)","Saturated fat (g)")],["sodium",h("נתרן (מ״ג)","Sodium (mg)")]] as const).map(([key,label])=><Field key={key} label={label} type="number" min={0} step="0.1" value={food.per100[key]??""} onChange={e=>setFood(f=>({...f,per100:{...f.per100,[key]:e.target.value===""?null:+e.target.value}}))}/>)}</div></Disclosure>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={favorite}
              onChange={(e) => setFavorite(e.target.checked)}
            />
            {h("שמירה במזונות האישיים", "Save to my foods")}
          </label>
          <Button type="button" disabled={busy} onClick={() => void addManual()}>
            {h("הוספת מזון", "Add food")}
          </Button>
        </div>
      )}
      {!manual && <Button type="button" variant="ghost" disabled={busy} className="food-manual-entry" aria-label={h("מזון חדש / הזנה ידנית", "New food / manual entry")} onClick={()=>{setManual(true);setCamera(false)}}><PenLine size={17}/>{h("לא מצאתם? הוספה ידנית", "Can’t find it? Add manually")}</Button>}
      <details className="text-xs text-muted-foreground"><summary>{h("מקורות המידע", "Data sources")}</summary><p className="text-xs text-muted-foreground">
        {h(
          "מקורות: USDA FoodData Central (CC0), Open Food Facts (ODbL), ותוויות שאישרת. הכיסוי למוצרים ישראליים אינו מלא.",
          "Sources: USDA FoodData Central (CC0), Open Food Facts (ODbL), and labels you confirm. Israeli product coverage is incomplete.",
        )}
      </p></details>
    </div>
  );
}

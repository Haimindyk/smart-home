"use client";
import { useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { useHealthStore } from "@/lib/health/store";
import { useHealthText } from "@/lib/health/i18n";
import { productPortion } from "@/lib/health/food-portions";
import { foodSchema, mealItemSchema, unitWeightSchema, type HealthRow, type MealItem } from "@/lib/health/model";
import { isAutomaticMealTitle, mealTitle } from "@/lib/health/meal-presentation";
import { Field, SelectField } from "./shared";

// The user selects the exact product AND unit count. A visual category match
// alone cannot establish a brand, portion count or package weight.
export function MealPortion({ meal, item, onDone }: { meal: HealthRow<"meals">; item: MealItem; onDone: () => void }) {
  const h = useHealthText();
  const foods = useHealthStore((s) => s.data.personal_foods);
  const [productId, setProductId] = useState("");
  const [amount, setAmount] = useState(String(item.quantity));
  const [upper, setUpper] = useState("");
  const [remember, setRemember] = useState(false), [name, setName] = useState(item.food.name);
  const savedProductId = useRef(crypto.randomUUID());
  const [units, setUnits] = useState("1");
  const [busy, setBusy] = useState(false), [error, setError] = useState("");
  const lock = useRef(false);
  const candidates = foods.filter((f) => f.data.unitWeight && f.data.basis === item.food.basis);
  async function save() {
    if (lock.current) return;
    lock.current = true; setBusy(true); setError("");
    try {
      const state = useHealthStore.getState();
      const latest = state.data.meals.find((m) => m.id === meal.id);
      if (state.owner !== meal.owner_user_id || !latest || latest.version !== meal.version)
        throw new Error("version_conflict");
      let product = state.data.personal_foods.find((f) => f.id === productId)?.data;
      if (productId && (!product?.unitWeight || product.basis !== item.food.basis))
        throw new Error("product_unavailable");
      const range = product?.unitWeight ?? unitWeightSchema.parse({ low: Number(amount), high: Number(upper || amount) });
      if (!productId && remember) {
        product = foodSchema.parse({ ...item.food, id: savedProductId.current, name, unitWeight: range });
        const existing = state.data.personal_foods.find((f) => f.data.id === product!.id);
        await state.save("personal_foods", product, existing, savedProductId.current);
        const current = useHealthStore.getState();
        if (current.owner !== meal.owner_user_id || current.data.meals.find((m) => m.id === meal.id)?.version !== meal.version)
          throw new Error("version_conflict");
      }
      const replacement = mealItemSchema.parse({
        ...item,
        ...(product ? productPortion(product, productId ? Number(units) : 1) : {
          quantity: (range.low + range.high) / 2,
          quantityRange: range,
          assumption: h("כמות שהזנת; הערכים התזונתיים נשארו ממקור המזון", "Amount you entered; nutrition retains its food source"),
        }),
      });
      const items = latest.data.items.map((i) => i.id === item.id ? replacement : i);
      await state.save("meals", { ...latest.data, items, name: isAutomaticMealTitle(latest.data) ? mealTitle(items) : latest.data.name }, latest);
      onDone();
    } catch {
      setError(h("לא נשמר. בדקו את הכמות ופתחו את הארוחה מחדש אם עודכנה.", "Not saved. Check the amount; reopen the meal if it changed."));
    } finally { lock.current = false; setBusy(false); }
  }
  return <div className="grid gap-3 rounded-2xl border p-4">
    <strong>{item.food.name}</strong>
    {candidates.length > 0 && <SelectField label={h("מוצר שמור", "Saved product")} value={productId} disabled={busy} onChange={(e) => setProductId(e.target.value)}>
      <option value="">{h("הזנת כמות", "Enter amount")}</option>
      {candidates.map((f) => <option key={f.id} value={f.id}>{f.data.name} · {f.data.unitWeight!.low}–{f.data.unitWeight!.high} {f.data.basis}</option>)}
    </SelectField>}
    {productId ? <Field label={h("מספר יחידות", "Number of units")} type="number" min="0.1" step="0.1" disabled={busy} value={units} onChange={(e) => setUnits(e.target.value)} /> : <>
      <Field label={`${h("כמות", "Amount")} (${item.food.basis})`} type="number" min="0.1" max="10000" step="0.1" disabled={busy} value={amount} onChange={(e) => setAmount(e.target.value)} />
      <details><summary className="text-sm">{h("טווח משקל או שמירת מוצר", "Weight range or save product")}</summary>
        <div className="mt-3 grid gap-3">
          <Field label={`${h("עד", "Up to")} (${item.food.basis})`} type="number" min="0.1" max="10000" step="0.1" disabled={busy} value={upper} placeholder={amount} onChange={(e) => setUpper(e.target.value)} />
          <label className="flex items-center gap-2 text-sm"><input type="checkbox" disabled={busy} checked={remember} onChange={(e) => setRemember(e.target.checked)} />{h("שמירת המשקל ליחידה אחת של מוצר מסוים", "Save this weight for one unit of a specific product")}</label>
          {remember && <Field label={h("שם מוצר ייחודי", "Specific product name")} disabled={busy} value={name} maxLength={200} onChange={(e) => setName(e.target.value)} />}
        </div>
      </details>
    </>}
    <div className="flex gap-2">
      <Button disabled={busy} onClick={() => void save()}>{h("עדכון", "Update")}</Button>
      <Button disabled={busy} variant="ghost" onClick={onDone}>{h("ביטול", "Cancel")}</Button>
    </div>
    {error && <p role="alert" className="text-sm">{error}</p>}
  </div>;
}

"use client";
import { useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { lookupFood } from "@/lib/health/api";
import { foodFromPrintedLabel } from "@/lib/health/product-label";
import { type Food, type MealItem } from "@/lib/health/model";
import { useHealthStore } from "@/lib/health/store";
import { useHealthText } from "@/lib/health/i18n";
import { BarcodeCamera } from "./barcode-camera";
import { ErrorText, Field, SelectField, Disclosure, ChoiceTabs } from "./shared";

export function ProductLabel({ onAdd }: { onAdd: (item: MealItem) => void }) {
  const h = useHealthText(),
    owner = useHealthStore((s) => s.owner);
  const [barcode, setBarcode] = useState(""),
    [camera, setCamera] = useState(false),
    [busy, setBusy] = useState(false);
  const [food, setFood] = useState<Food | null>(null),
    [error, setError] = useState<string | null>(null),
    [message, setMessage] = useState("");
  const [manual, setManual] = useState(false),
    [name, setName] = useState(""),
    [basis, setBasis] = useState<"g" | "ml">("g"),
    [printedAmount, setPrintedAmount] = useState("100");
  const [values, setValues] = useState<Record<string, string>>({}),
    [confirmed, setConfirmed] = useState(false),
    [quantity, setQuantity] = useState("100");
  const [energyUnit, setEnergyUnit] = useState<"kcal" | "kJ">("kcal"),
    [sodiumUnit, setSodiumUnit] = useState<"mg" | "g" | "salt_g">("mg");
  const request = useRef(0);
  async function search(code = barcode) {
    const serial = ++request.current;
    setBusy(true);
    setError(null);
    setFood(null);
    setMessage("");
    setConfirmed(false);
    setManual(false);
    try {
      const response = await lookupFood("", code, true, owner ?? undefined);
      if (
        serial !== request.current ||
        useHealthStore.getState().owner !== owner
      )
        return;
      const found = response.foods.find(
        (f) =>
          f.source === "openfoodfacts" ||
          (f.source === "label" && f.sourceId?.startsWith("label:printed-confirmed:v1:")),
      );
      if (found) setFood(found);
      else {
        setName(response.name ?? "");
        setManual(true);
        setMessage(
          h(
            "אין נתונים מלאים למוצר. הזינו את הערכים מהאריזה.",
            "No complete product data. Enter the printed package values.",
          ),
        );
      }
    } catch (e) {
      if (
        serial === request.current &&
        useHealthStore.getState().owner === owner
      )
        setError(e instanceof Error ? e.message : "failed");
    } finally {
      if (
        serial === request.current &&
        useHealthStore.getState().owner === owner
      )
        setBusy(false);
    }
  }
  function add() {
    setError(null);
    try {
      if (useHealthStore.getState().owner !== owner)
        throw new Error("session_mismatch");
      if (!confirmed) throw new Error("label_confirmation_required");
      const amount = Number(quantity);
      if (!Number.isFinite(amount) || amount <= 0 || amount > 10000)
        throw new Error("invalid_input");
      const selected = manual
        ? foodFromPrintedLabel({
            name,
            basis,
            printedAmount,
            values,
            confirmed,
            energyUnit,
            sodiumUnit,
            barcode: /^\d{8,14}$/.test(barcode) ? barcode : undefined,
          })
        : food;
      if (!selected || !["openfoodfacts", "label"].includes(selected.source))
        throw new Error("label_values_required");
      onAdd({ id: crypto.randomUUID(), food: selected, quantity: amount });
      setFood(null);
      setManual(false); setEnergyUnit("kcal"); setSodiumUnit("mg"); setPrintedAmount("100"); setBasis("g"); setQuantity("100");
      setConfirmed(false);
      setValues({});
      setName("");
      setMessage(
        h(
          "המוצר נוסף לארוחה. אפשר להוסיף עוד או לשמור ביומן.",
          "Product added. Add another or save the meal to your diary.",
        ),
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    }
  }
  const valueField = (key:string,label:string) => <Field key={key} label={label} type="number" min="0" step="any" value={values[key]??""} onChange={e=>{setValues(v=>({...v,[key]:e.target.value}));setConfirmed(false)}}/>;
  return <section className="product-entry grid gap-4" aria-label={h("ערכי מוצר מהאריזה", "Product label values")}>
    <ChoiceTabs label={h("דרך זיהוי המוצר", "Product entry method")} value={manual?"printed":"barcode"} onChange={next=>{++request.current;setBusy(false);setManual(next==="printed");setCamera(false);setFood(null);setConfirmed(false);setError(null)}} options={[{value:"barcode",label:h("ברקוד", "Barcode")},{value:"printed",label:h("מהאריזה", "Printed values")}]} />
    <p className="text-xs text-muted-foreground">{h("נתוני מוצר מהמאגר או מהאריזה. ללא הערכת AI.", "Product data from the database or package. No AI estimates.")}</p>
    <ErrorText error={error}/>
    {!manual && <><form className="flex flex-wrap items-end gap-2" onSubmit={e=>{e.preventDefault();void search()}}>
      <div className="min-w-0 flex-1"><Field label={h("ברקוד המוצר", "Product barcode")} inputMode="numeric" value={barcode} onChange={e=>{++request.current;setBusy(false);setBarcode(e.target.value.replace(/\D/g,""));setFood(null);setConfirmed(false)}}/></div>
      <Button type="submit" disabled={busy||!/^\d{8,14}$/.test(barcode)}>{busy?h("מחפש…","Looking up…"):h("איתור מוצר", "Find product")}</Button>
    </form><Button type="button" variant="outline" className="product-camera-action" onClick={()=>setCamera(v=>!v)}>{h("סריקת ברקוד במצלמה", "Scan barcode with camera")}</Button>
    {camera&&<BarcodeCamera onCode={code=>{setBarcode(code);setCamera(false);void search(code)}}/>}</>}
    {message&&<p role="status" className="text-sm">{message}</p>}
    {food&&!manual&&<div className="product-result"><strong>{food.name}</strong><p>{h("לכל 100", "Per 100")} {food.basis}: {food.per100.kcal} kcal · P {food.per100.protein} / C {food.per100.carbs} / F {food.per100.fat}</p><small>{food.source==="openfoodfacts"?"Open Food Facts":h("תווית שאושרה", "Confirmed label")}</small></div>}
    {manual&&<div className="grid gap-4">
      <Field label={h("שם המוצר שעל האריזה", "Product name on package")} value={name} onChange={e=>{setName(e.target.value);setConfirmed(false)}}/>
      <div className="grid grid-cols-2 gap-3"><Field label={h("הערכים המודפסים הם לכמות", "Printed values are per amount")} type="number" min="0.1" value={printedAmount} onChange={e=>{setPrintedAmount(e.target.value);setConfirmed(false)}}/><SelectField label={h("יחידת התווית", "Label unit")} value={basis} onChange={e=>{setBasis(e.target.value as "g"|"ml");setConfirmed(false)}}><option value="g">{h("גרם", "grams")}</option><option value="ml">{h("מ״ל", "ml")}</option></SelectField></div>
      <p className="text-xs text-muted-foreground">{h("ארבעת הערכים הראשיים נדרשים. אפס מזינים במפורש.", "All four main values are required. Enter zero explicitly.")}</p>
      <div className="grid grid-cols-2 gap-3">{valueField("kcal",energyUnit==="kJ"?h("אנרגיה (קילו־ג׳אול)","Energy (kJ)"):h("קלוריות (קק״ל)","Calories (kcal)"))}{valueField("protein",h("חלבון (גרם)","Protein (g)"))}{valueField("carbs",h("פחמימות (גרם)","Carbohydrate (g)"))}{valueField("fat",h("שומן (גרם)","Fat (g)"))}</div>
      <Disclosure title={h("ערכים נוספים ויחידות", "More nutrients and units")}><div className="grid gap-3"><div className="grid grid-cols-2 gap-3"><SelectField label={h("יחידת האנרגיה המודפסת", "Printed energy unit")} value={energyUnit} onChange={e=>{setEnergyUnit(e.target.value as typeof energyUnit);setConfirmed(false)}}><option value="kcal">kcal</option><option value="kJ">kJ</option></SelectField><SelectField label={h("יחידת הנתרן או המלח המודפסת", "Printed sodium or salt unit")} value={sodiumUnit} onChange={e=>{setSodiumUnit(e.target.value as typeof sodiumUnit);setConfirmed(false)}}><option value="mg">{h("נתרן במ״ג","Sodium in mg")}</option><option value="g">{h("נתרן בגרם","Sodium in g")}</option><option value="salt_g">{h("מלח בגרם","Salt in g")}</option></SelectField></div>
      <div className="grid grid-cols-2 gap-3">{valueField("fiber",h("סיבים (גרם, אופציונלי)","Fiber (g, optional)"))}{valueField("sugar",h("סוכר (גרם, אופציונלי)","Sugar (g, optional)"))}{valueField("saturatedFat",h("שומן רווי (גרם, אופציונלי)","Saturated fat (g, optional)"))}{valueField("sodium",sodiumUnit==="salt_g"?h("מלח (גרם, אופציונלי)","Salt (g, optional)"):sodiumUnit==="g"?h("נתרן (גרם, אופציונלי)","Sodium (g, optional)"):h("נתרן (מ״ג, אופציונלי)","Sodium (mg, optional)"))}</div></div></Disclosure>
    </div>}
    {(food||manual)&&<><Field label={`${h("כמות שאכלת", "Amount eaten")} (${manual?basis:food?.basis??"g"})`} type="number" min="0.1" max="10000" step="any" value={quantity} onChange={e=>setQuantity(e.target.value)}/><label className="flex items-start gap-2 text-sm"><input type="checkbox" checked={confirmed} onChange={e=>setConfirmed(e.target.checked)}/>{h("בדקתי שהמוצר, היחידה והערכים תואמים לאריזה", "I checked that the product, unit and values match the package")}</label><Button disabled={!confirmed||busy} onClick={add}>{h("הוספה לארוחה", "Add to meal")}</Button></>}
    <Disclosure className="health-help" title={h("מקור הנתונים ודיוק", "Data source and accuracy")}><p>{h("Open Food Facts הוא מאגר קהילתי (ODbL). יש לבדוק שהמוצר והערכים תואמים לאריזה. ערכים שלא ידועים נשארים ריקים. ערכי מנה מחושבים ל־100 גרם או מ״ל, בלי להמיר ביניהם.", "Open Food Facts is a community database (ODbL). Check the product and values against your package. Unknown values stay empty. Printed servings are scaled to 100 g or ml, without converting between mass and volume.")}</p></Disclosure>
  </section>;
}

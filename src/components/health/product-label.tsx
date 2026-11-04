"use client";
import { useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { lookupFood } from "@/lib/health/api";
import { foodFromPrintedLabel } from "@/lib/health/product-label";
import { type Food, type MealItem } from "@/lib/health/model";
import { useHealthStore } from "@/lib/health/store";
import { useHealthText } from "@/lib/health/i18n";
import { BarcodeCamera } from "./barcode-camera";
import { ErrorText, Field, SelectField } from "./shared";

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
            "אין נתונים מלאים למוצר. העתיקו את הערכים המודפסים מהאריזה; לא יושלמו ערכים בעזרת AI.",
            "No complete product data. Copy the printed values from the package; AI will not fill in missing values.",
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
      setConfirmed(false);
      setValues({});
      setName("");
      setMessage(
        h(
          "המוצר נוסף לטיוטה. יש לשמור את הארוחה כדי להוסיף ליומן.",
          "Product added to the draft. Save the meal to add it to your diary.",
        ),
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    }
  }
  return (
    <section
      className="grid gap-3 rounded-2xl border bg-background p-4 text-foreground"
      aria-label={h("ערכי מוצר מהאריזה", "Product label values")}
    >
      <p className="text-sm">
        {h(
          "סרקו את ברקוד המוצר כדי לקבל נתונים מ־Open Food Facts. זהו מאגר קהילתי — יש לבדוק התאמה למוצר ולאריזה. ערכי התווית אינם מוערכים ב־AI.",
          "Scan the product barcode for Open Food Facts data. This is a community database: check the product and package match. Label values are never estimated by AI.",
        )}
      </p>
      <ErrorText error={error} />
      <form
        className="flex flex-wrap items-end gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          void search();
        }}
      >
        <Field
          label={h("ברקוד המוצר", "Product barcode")}
          inputMode="numeric"
          value={barcode}
          onChange={(e) => {
            ++request.current;
            setBusy(false);
            setBarcode(e.target.value.replace(/\D/g, ""));
            setFood(null);
            setConfirmed(false);
          }}
        />
        <Button type="submit" disabled={busy || !/^\d{8,14}$/.test(barcode)}>
          {h("איתור מוצר", "Find product")}
        </Button>
        <Button
          type="button"
          variant="outline"
          onClick={() => setCamera((v) => !v)}
        >
          {h("סריקת ברקוד במצלמה", "Scan barcode with camera")}
        </Button>
      </form>
      {camera && (
        <BarcodeCamera
          onCode={(code) => {
            setBarcode(code);
            setCamera(false);
            void search(code);
          }}
        />
      )}
      <Button
        variant="outline"
        disabled={busy}
        onClick={() => {
          ++request.current;
          setManual((v) => !v);
          setFood(null);
          setConfirmed(false);
          setError(null);
        }}
      >
        {h("העתקת ערכים מהאריזה", "Copy values from package")}
      </Button>
      {message && (
        <p role="status" className="text-sm">
          {message}
        </p>
      )}
      {food && !manual && (
        <div className="rounded-xl border p-3 text-sm">
          <strong>{food.name}</strong>
          <p>
            {h("לכל 100", "Per 100")} {food.basis}: {food.per100.kcal} kcal · P{" "}
            {food.per100.protein} / C {food.per100.carbs} / F {food.per100.fat}
          </p>
          <p>
            {food.source === "openfoodfacts"
              ? "Open Food Facts (ODbL)"
              : h(
                  "תווית שהוזנה ואושרה בעבר",
                  "Previously entered and confirmed label",
                )}
          </p>
        </div>
      )}
      {manual && (
        <div className="grid gap-3">
          <Field
            label={h("שם המוצר שעל האריזה", "Product name on package")}
            value={name}
            onChange={(e) => {
              setName(e.target.value);
              setConfirmed(false);
            }}
          />
          <div className="grid grid-cols-2 gap-2">
            <Field
              label={h(
                "הערכים המודפסים הם לכמות",
                "Printed values are per amount",
              )}
              type="number"
              min="0.1"
              value={printedAmount}
              onChange={(e) => {
                setPrintedAmount(e.target.value);
                setConfirmed(false);
              }}
            />
            <SelectField
              label={h("יחידת התווית", "Label unit")}
              value={basis}
              onChange={(e) => {
                setBasis(e.target.value as "g" | "ml");
                setConfirmed(false);
              }}
            >
              <option value="g">{h("גרם", "grams")}</option>
              <option value="ml">{h("מ״ל", "ml")}</option>
            </SelectField>
          </div>
          <p className="text-xs">
            {h(
              "למשל, אם הערכים הם למנה של 30 גרם, הזינו 30. שדות חובה: קלוריות, חלבון, פחמימות ושומן. ערך אפס יש להזין במפורש; ערך לא ידוע אינו אפס.",
              "For a 30 g serving, enter 30. Calories, protein, carbohydrate and fat are required. Enter zero explicitly; an unknown value is not zero.",
            )}
          </p>
          <div className="grid grid-cols-2 gap-2">
            <SelectField
              label={h("יחידת האנרגיה המודפסת", "Printed energy unit")}
              value={energyUnit}
              onChange={(e) => {
                setEnergyUnit(e.target.value as typeof energyUnit);
                setConfirmed(false);
              }}
            >
              <option value="kcal">kcal</option>
              <option value="kJ">kJ</option>
            </SelectField>
            <SelectField
              label={h(
                "יחידת הנתרן או המלח המודפסת",
                "Printed sodium or salt unit",
              )}
              value={sodiumUnit}
              onChange={(e) => {
                setSodiumUnit(e.target.value as typeof sodiumUnit);
                setConfirmed(false);
              }}
            >
              <option value="mg">{h("נתרן במ״ג", "Sodium in mg")}</option>
              <option value="g">{h("נתרן בגרם", "Sodium in g")}</option>
              <option value="salt_g">{h("מלח בגרם", "Salt in g")}</option>
            </SelectField>
          </div>
          <div className="grid grid-cols-2 gap-2">
            {(
              [
                [
                  "kcal",
                  energyUnit === "kJ"
                    ? h("אנרגיה (קילו־ג׳אול)", "Energy (kJ)")
                    : h("קלוריות (קק״ל)", "Calories (kcal)"),
                ],
                ["protein", h("חלבון (גרם)", "Protein (g)")],
                ["carbs", h("פחמימות (גרם)", "Carbohydrate (g)")],
                ["fat", h("שומן (גרם)", "Fat (g)")],
                ["fiber", h("סיבים (גרם, אופציונלי)", "Fiber (g, optional)")],
                ["sugar", h("סוכר (גרם, אופציונלי)", "Sugar (g, optional)")],
                [
                  "saturatedFat",
                  h(
                    "שומן רווי (גרם, אופציונלי)",
                    "Saturated fat (g, optional)",
                  ),
                ],
                [
                  "sodium",
                  sodiumUnit === "salt_g"
                    ? h("מלח (גרם, אופציונלי)", "Salt (g, optional)")
                    : sodiumUnit === "g"
                      ? h("נתרן (גרם, אופציונלי)", "Sodium (g, optional)")
                      : h("נתרן (מ״ג, אופציונלי)", "Sodium (mg, optional)"),
                ],
              ] as const
            ).map(([key, label]) => (
              <Field
                key={key}
                label={label}
                type="number"
                min="0"
                step="any"
                value={values[key] ?? ""}
                onChange={(e) => {
                  setValues((v) => ({ ...v, [key]: e.target.value }));
                  setConfirmed(false);
                }}
              />
            ))}
          </div>
        </div>
      )}
      {(food || manual) && (
        <>
          <Field
            label={h("כמות שנאכלה", "Amount eaten")}
            type="number"
            min="0.1"
            max="10000"
            step="any"
            value={quantity}
            onChange={(e) => setQuantity(e.target.value)}
          />
          <p className="text-xs">
            {h(
              "הכמות באותה יחידה של התווית או המאגר. אין המרה אוטומטית בין גרם למ״ל.",
              "Use the same unit as the label or database. Grams and ml are not automatically converted.",
            )}
          </p>
          <label className="flex items-start gap-2 text-sm">
            <input
              type="checkbox"
              checked={confirmed}
              onChange={(e) => setConfirmed(e.target.checked)}
            />
            {h(
              "בדקתי שהמוצר, היחידה והערכים תואמים לאריזה",
              "I checked that the product, unit and values match the package",
            )}
          </label>
          <Button disabled={!confirmed || busy} onClick={add}>
            {h("הוספת המוצר לטיוטה", "Add product to draft")}
          </Button>
        </>
      )}
    </section>
  );
}

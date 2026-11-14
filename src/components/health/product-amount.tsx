"use client";
import { type Food } from "@/lib/health/model";
import { type ProductAmount, productAmount } from "@/lib/health/product-amount";
import { useHealthText } from "@/lib/health/i18n";
import { ChoiceTabs, Field, round } from "./shared";

export function ProductAmountInput({ food, basis, value, onChange }: {
  food?: Food | null;
  basis: "g" | "ml";
  value: ProductAmount;
  onChange: (value: ProductAmount) => void;
}) {
  const h = useHealthText();
  let amount: number | null = null;
  try { if (food) amount = productAmount(food, value).quantity; } catch { /* Incomplete field; add stays disabled. */ }
  const unit = basis === "g" ? h("גרם", "g") : h("מ״ל", "ml");
  const known = food?.unitWeight;
  return <section className="product-amount grid gap-3" aria-label={h("כמות המוצר", "Product amount")}>
    <h3 className="font-semibold">{h("כמה אכלת?", "How much did you eat?")}</h3>
    <ChoiceTabs label={h("יחידת כמות", "Amount unit")} value={value.mode} onChange={(mode) => onChange({ ...value, mode: mode as ProductAmount["mode"], quantity: mode === "units" ? "1" : "100" })} options={[{ value: "amount", label: unit }, { value: "units", label: h("יחידות", "Units") }]} />
    <div className={value.mode === "units" ? "grid grid-cols-2 gap-3" : ""}>
      <Field label={value.mode === "units" ? h("מספר יחידות", "Number of units") : `${h("כמות שאכלת", "Amount eaten")} (${basis})`} type="number" inputMode="decimal" min="0.1" max={value.mode === "units" ? "1000" : "10000"} step="any" value={value.quantity} onChange={(e) => onChange({ ...value, quantity: e.target.value })} />
      {value.mode === "units" && <Field label={`${unit} ${h("ליחידה", "per unit")}`} type="number" inputMode="decimal" min="0.1" max="10000" step="any" value={value.unitEdited ? value.unitAmount : value.unitAmount || (known ? String((known.low + known.high) / 2) : "")} placeholder={h("לפי האריזה", "From package")} onChange={(e) => onChange({ ...value, unitAmount: e.target.value, unitEdited: true })} />}
    </div>
    {value.mode === "units" && !known && !value.unitAmount && <p className="text-xs text-muted-foreground">{h("הזינו את הכמות ליחידה שמופיעה על האריזה", "Enter one unit’s size from the package")}</p>}
    {amount !== null && food && <p className="product-amount-total" role="status">{h("סה״כ", "Total")} {round(amount)} {unit} · <strong>{round(food.per100.kcal * amount / 100)} {h("קל׳", "kcal")}</strong></p>}
  </section>;
}

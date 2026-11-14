import { type Food, type MealItem, mealItemSchema, unitWeightSchema } from "./model";
import { productPortion } from "./food-portions";

export type ProductAmount = { mode: "amount" | "units"; quantity: string; unitAmount: string; unitEdited?: boolean };
export const defaultProductAmount = (): ProductAmount => ({ mode: "amount", quantity: "100", unitAmount: "" });
const positive = (value: string, max: number) => {
  const n = Number(value.trim().replace(",", "."));
  if (!Number.isFinite(n) || n <= 0 || n > max) throw new Error("invalid_input");
  return n;
};

export function productAmount(food: Food, selection: ProductAmount) {
  if (selection.mode === "amount") return { food, quantity: positive(selection.quantity, 10000) };
  const units = positive(selection.quantity, 1000);
  const weight = selection.unitAmount.trim()
    ? unitWeightSchema.parse({ low: positive(selection.unitAmount, 10000), high: positive(selection.unitAmount, 10000) })
    : selection.unitEdited ? undefined : food.unitWeight;
  if (!weight) throw new Error("unit_amount_required");
  // Unit size has the food's declared basis; no ml-to-g density conversion.
  return productPortion({ ...food, unitWeight: weight }, units);
}

export function productAmountItem(food: Food, selection: ProductAmount): MealItem {
  return mealItemSchema.parse({ id: crypto.randomUUID(), ...productAmount(food, selection) });
}

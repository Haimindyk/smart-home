import { foodSchema, mealItemSchema, type Food, type MealItem } from "./model";

export function productPortion(food: Food, units = 1): Pick<MealItem, "food" | "quantity" | "quantityRange" | "assumption"> {
  const parsed = foodSchema.parse(food);
  if (!Number.isFinite(units) || units <= 0 || units > 1000 || !parsed.unitWeight)
    throw new Error("invalid_product_units");
  const low = parsed.unitWeight.low * units, high = parsed.unitWeight.high * units;
  if (high > 10000) throw new Error("invalid_product_units");
  return {
    food: parsed,
    quantity: (low + high) / 2,
    quantityRange: { low, high },
    assumption: `כמות לפי ${units} יחידות של מוצר שאישרת; המשקל בטווח ${low}–${high} ${parsed.basis}. הערכים התזונתיים נשארו ממקור המזון.`,
  };
}

export function foodPickerItem(food: Food): MealItem {
  return mealItemSchema.parse({
    id: crypto.randomUUID(),
    ...(food.unitWeight ? productPortion(food) : { food, quantity: food.servingSize ?? 100 }),
  });
}

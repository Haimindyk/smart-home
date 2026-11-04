import { foodSchema, type Food } from "./model";

export function foodFromPrintedLabel(input: {
  name: string;
  basis: "g" | "ml";
  printedAmount: string;
  values: Record<string, string>;
  confirmed: boolean;
  barcode?: string;
  energyUnit?: "kcal" | "kJ";
  sodiumUnit?: "mg" | "g" | "salt_g";
}): Food {
  if (!input.confirmed) throw new Error("label_confirmation_required");
  const read = (v: string | undefined, required = false) => {
    if (!v?.trim()) {
      if (required) throw new Error("label_values_required");
      return null;
    }
    const n = Number(v.replace(",", "."));
    if (!Number.isFinite(n) || n < 0) throw new Error("invalid_input");
    return n;
  };
  const amount = read(input.printedAmount, true)!;
  if (amount <= 0 || amount > 10000) throw new Error("invalid_input");
  const per100 = Object.fromEntries(
    [
      "kcal",
      "protein",
      "carbs",
      "fat",
      "fiber",
      "sugar",
      "saturatedFat",
      "sodium",
    ].map((key) => {
      let value = read(
        input.values[key],
        ["kcal", "protein", "carbs", "fat"].includes(key),
      );
      if (value !== null && key === "kcal" && input.energyUnit === "kJ")
        value /= 4.184;
      if (value !== null && key === "sodium" && input.sodiumUnit === "g")
        value *= 1000;
      if (value !== null && key === "sodium" && input.sodiumUnit === "salt_g")
        value *= 1000 / 2.5;
      return [key, value === null ? null : (value * 100) / amount];
    }),
  );
  return foodSchema.parse({
    id: crypto.randomUUID(),
    name: input.name,
    basis: input.basis,
    source: "label",
    sourceId: "label:printed-confirmed:v1",
    per100,
    ...(input.barcode ? { barcode: input.barcode } : {}),
  });
}

"use client";
import { useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { useHealthStore } from "@/lib/health/store";
import { useHealthText } from "@/lib/health/i18n";
import { unitWeightSchema, type HealthRow } from "@/lib/health/model";
import { Field } from "./shared";

export function FoodUnitWeight({ row }: { row: HealthRow<"personal_foods"> }) {
  const h = useHealthText();
  const [editing, setEditing] = useState(false), [busy, setBusy] = useState(false);
  const [low, setLow] = useState(String(row.data.unitWeight?.low ?? ""));
  const [high, setHigh] = useState(String(row.data.unitWeight?.high ?? ""));
  const [error, setError] = useState("");
  const lock = useRef(false);
  async function save(clear = false) {
    if (lock.current) return;
    lock.current = true; setBusy(true); setError("");
    try {
      const state = useHealthStore.getState();
      const current = state.data.personal_foods.find((f) => f.id === row.id);
      if (!current || state.owner !== row.owner_user_id || current.version !== row.version)
        throw new Error("version_conflict");
      const unitWeight = clear ? undefined : unitWeightSchema.parse({ low: Number(low), high: Number(high || low) });
      await state.save("personal_foods", { ...current.data, unitWeight }, current);
      setEditing(false);
    } catch {
      setError(h("בדקו את הטווח ונסו שוב", "Check the range and try again"));
    } finally { lock.current = false; setBusy(false); }
  }
  return <div className="grid gap-2">
    <Button size="sm" variant="ghost" disabled={busy} onClick={() => { setLow(String(row.data.unitWeight?.low ?? "")); setHigh(String(row.data.unitWeight?.high ?? "")); setEditing(!editing); }}>
      {row.data.unitWeight ? `${row.data.unitWeight.low}–${row.data.unitWeight.high} ${row.data.basis} · ${h("ליחידה", "per unit")}` : h("משקל ליחידה", "Unit weight")}
    </Button>
    {editing && <div className="grid gap-3 rounded-2xl border p-3">
      <p className="text-sm">{h("ליחידה אחת של המוצר הזה, לפי האריזה או שקילה", "One unit of this product, from its package or a scale")}</p>
      <div className="grid grid-cols-2 gap-2">
        <Field label={`${h("מ־", "From")} (${row.data.basis})`} type="number" min="0.1" max="10000" step="0.1" value={low} onChange={(e) => setLow(e.target.value)} />
        <Field label={`${h("עד", "To")} (${row.data.basis})`} type="number" min="0.1" max="10000" step="0.1" value={high} placeholder={low} onChange={(e) => setHigh(e.target.value)} />
      </div>
      <div className="flex gap-2">
        <Button size="sm" disabled={busy || !low} onClick={() => void save()}>{h("שמירה", "Save")}</Button>
        {row.data.unitWeight && <Button size="sm" variant="ghost" disabled={busy} onClick={() => void save(true)}>{h("הסרת משקל", "Remove weight")}</Button>}
        <Button size="sm" variant="ghost" disabled={busy} onClick={() => setEditing(false)}>{h("ביטול", "Cancel")}</Button>
      </div>
      {error && <p role="alert" className="text-sm">{error}</p>}
    </div>}
  </div>;
}

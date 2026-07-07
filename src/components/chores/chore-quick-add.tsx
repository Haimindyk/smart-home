"use client";

import { useState } from "react";
import { Plus } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import type { ChoreFreq } from "@/types/domain";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

export function ChoreQuickAdd({ sectionId }: { sectionId: string }) {
  const createChore = useAppStore((s) => s.createChore);
  const t = useT();
  const [title, setTitle] = useState("");
  const [freq, setFreq] = useState<ChoreFreq>("daily");

  function submit() {
    if (!title.trim()) return;
    void createChore({ sectionId, title: title.trim(), freq });
    setTitle("");
  }

  return (
    <form
      className="mb-2 flex items-center gap-2 rounded-lg border bg-card px-2 py-1.5 shadow-sm"
      onSubmit={(e) => {
        e.preventDefault();
        submit();
      }}
    >
      <Plus className="size-4 shrink-0 text-muted-foreground" />
      <input
        dir="auto"
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        placeholder={t("addChore")}
        className="w-full bg-transparent text-sm outline-none"
      />
      <Select value={freq} onValueChange={(v) => v && setFreq(v as ChoreFreq)}>
        <SelectTrigger className="h-7 w-28 text-xs">
          <SelectValue>{(v: ChoreFreq) => t(v)}</SelectValue>
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="daily">{t("daily")}</SelectItem>
          <SelectItem value="weekly">{t("weekly")}</SelectItem>
          <SelectItem value="monthly">{t("monthly")}</SelectItem>
          <SelectItem value="as_needed">{t("as_needed")}</SelectItem>
        </SelectContent>
      </Select>
    </form>
  );
}

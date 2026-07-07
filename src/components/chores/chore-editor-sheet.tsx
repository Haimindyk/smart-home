"use client";

import { useMemo, useState } from "react";
import { Trash2 } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useLocaleStore, useT } from "@/lib/i18n/store";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetFooter,
} from "@/components/ui/sheet";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { AssigneeMultiSelect } from "@/components/tasks/assignee-multi-select";
import { MemberAvatar } from "@/components/identity/member-avatar";
import type { Chore, ChoreFreq } from "@/types/domain";

// Sunday-first weekday indices (matches JS Date#getDay()); Jan 1 2023 was a Sunday.
const WEEKDAY_REF = Array.from({ length: 7 }, (_, i) => new Date(2023, 0, 1 + i));

export function ChoreEditorSheet({
  choreId,
  onOpenChange,
}: {
  choreId: string | null;
  onOpenChange: (open: boolean) => void;
}) {
  const chore = useAppStore((s) => (choreId ? s.chores[choreId] : undefined));
  const members = useAppStore((s) => s.members);
  const choreCompletions = useAppStore((s) => s.choreCompletions);
  const updateChore = useAppStore((s) => s.updateChore);
  const deleteChore = useAppStore((s) => s.deleteChore);
  const locale = useLocaleStore((s) => s.locale);
  const t = useT();

  const [local, setLocal] = useState<Chore | undefined>(chore);
  // Re-sync `local` whenever the store's chore reference changes (own commits or
  // a realtime echo from another device) — adjusting state during render per
  // https://react.dev/learn/you-might-not-need-an-effect#adjusting-some-state-when-a-prop-changes
  const [syncedChore, setSyncedChore] = useState(chore);
  if (chore !== syncedChore) {
    setSyncedChore(chore);
    setLocal(chore);
  }

  const lastCompletion = useMemo(() => {
    if (!choreId) return undefined;
    return Object.values(choreCompletions)
      .filter((c) => c.chore_id === choreId)
      .sort((a, b) => (a.completed_at > b.completed_at ? -1 : 1))[0];
  }, [choreCompletions, choreId]);

  const weekdayLabels = useMemo(() => {
    const intlLocale = locale === "he" ? "he-IL" : "en-US";
    return WEEKDAY_REF.map((d) => d.toLocaleDateString(intlLocale, { weekday: "short" }));
  }, [locale]);

  if (!chore || !local) return null;

  function commit(patch: Partial<Chore>) {
    if (!choreId) return;
    setLocal((prev) => (prev ? { ...prev, ...patch } : prev));
    void updateChore(choreId, patch);
  }

  function toggleWeekday(day: number) {
    const current = local?.weekdays ?? [];
    const next = current.includes(day) ? current.filter((d) => d !== day) : [...current, day].sort();
    commit({ weekdays: next.length > 0 ? next : null });
  }

  return (
    <Sheet open={!!choreId} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="mx-auto max-h-[90vh] max-w-2xl overflow-y-auto rounded-t-2xl">
        <SheetHeader>
          <SheetTitle className="sr-only">
            {t("editChore")}: {local.title}
          </SheetTitle>
        </SheetHeader>
        <div className="flex flex-col gap-5 px-4 pb-4">
          <div className="flex items-start gap-2">
            <Input
              value={local.emoji ?? ""}
              onChange={(e) => commit({ emoji: e.target.value.slice(0, 4) })}
              placeholder="🙂"
              className="w-14 text-center text-lg"
            />
            <Input
              dir="auto"
              value={local.title}
              onChange={(e) => setLocal({ ...local, title: e.target.value })}
              onBlur={(e) => commit({ title: e.target.value })}
              className="flex-1 text-base font-medium"
            />
          </div>

          <div className="grid gap-2">
            <Label>{t("notes")}</Label>
            <Textarea
              dir="auto"
              value={local.notes ?? ""}
              onChange={(e) => setLocal({ ...local, notes: e.target.value })}
              onBlur={(e) => commit({ notes: e.target.value || null })}
              rows={3}
            />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="grid gap-2">
              <Label>{t("frequency")}</Label>
              <Select value={local.freq} onValueChange={(v) => v && commit({ freq: v as ChoreFreq })}>
                <SelectTrigger>
                  <SelectValue>{(v: ChoreFreq) => t(v)}</SelectValue>
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="daily">{t("daily")}</SelectItem>
                  <SelectItem value="weekly">{t("weekly")}</SelectItem>
                  <SelectItem value="monthly">{t("monthly")}</SelectItem>
                  <SelectItem value="as_needed">{t("as_needed")}</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="grid gap-2">
              <Label>{t("every")}</Label>
              <Input
                type="number"
                min={1}
                value={local.interval_n}
                onChange={(e) => setLocal({ ...local, interval_n: Number(e.target.value) || 1 })}
                onBlur={(e) => commit({ interval_n: Number(e.target.value) || 1 })}
              />
            </div>
          </div>

          {local.freq === "weekly" && (
            <div className="grid gap-2">
              <Label>{t("weekdays")}</Label>
              <div className="flex flex-wrap gap-1.5">
                {weekdayLabels.map((label, day) => (
                  <Button
                    key={day}
                    type="button"
                    variant={(local.weekdays ?? []).includes(day) ? "default" : "outline"}
                    size="sm"
                    className="h-8 min-w-10 px-2"
                    onClick={() => toggleWeekday(day)}
                  >
                    {label}
                  </Button>
                ))}
              </div>
            </div>
          )}

          <div className="grid gap-4 sm:grid-cols-2">
            <div className="grid gap-2">
              <Label>{t("assignees")}</Label>
              <AssigneeMultiSelect
                assigneeKind={local.assignee_kind}
                assigneeMemberIds={local.assignee_member_ids}
                allowUnassigned={false}
                onChange={(next) =>
                  commit({
                    assignee_kind: next.assignee_kind as Chore["assignee_kind"],
                    assignee_member_ids: next.assignee_member_ids,
                  })
                }
              />
            </div>

            {lastCompletion && (
              <div className="grid gap-2">
                <Label>{t("doneBy")}</Label>
                <p className="flex h-8 items-center gap-1.5 text-sm text-muted-foreground">
                  <MemberAvatar member={members[lastCompletion.completed_by]} className="size-5" />
                  {members[lastCompletion.completed_by]?.display_name ?? "?"}
                </p>
              </div>
            )}
          </div>
        </div>

        <SheetFooter className="flex-row justify-between border-t pt-4">
          <Button
            variant="destructive"
            size="sm"
            className="gap-2"
            onClick={() => {
              void deleteChore(choreId!);
              onOpenChange(false);
            }}
          >
            <Trash2 className="size-4" />
            {t("delete")}
          </Button>
        </SheetFooter>
      </SheetContent>
    </Sheet>
  );
}

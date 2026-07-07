"use client";

import { useState } from "react";
import { format } from "date-fns";
import { CalendarIcon, Trash2, X } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
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
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Calendar } from "@/components/ui/calendar";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { AssigneeMultiSelect } from "@/components/tasks/assignee-multi-select";
import type { Task, SectionKind } from "@/types/domain";

const PRIORITIES = [
  { value: "0", labelHe: "ללא", labelEn: "None" },
  { value: "1", labelHe: "נמוכה", labelEn: "Low" },
  { value: "2", labelHe: "בינונית", labelEn: "Medium" },
  { value: "3", labelHe: "דחוף", labelEn: "Urgent" },
];

export function TaskEditorSheet({
  taskId,
  sectionKind,
  onOpenChange,
}: {
  taskId: string | null;
  sectionKind: SectionKind;
  onOpenChange: (open: boolean) => void;
}) {
  const task = useAppStore((s) => (taskId ? s.tasks[taskId] : undefined));
  const members = useAppStore((s) => s.members);
  const sections = useAppStore((s) => s.sections);
  const updateTask = useAppStore((s) => s.updateTask);
  const softDeleteTask = useAppStore((s) => s.softDeleteTask);
  const t = useT();

  const [local, setLocal] = useState<Task | undefined>(task);
  const [tagInput, setTagInput] = useState("");
  // Re-sync `local` whenever the store's task reference changes (own commits or
  // a realtime echo from another device) — adjusting state during render per
  // https://react.dev/learn/you-might-not-need-an-effect#adjusting-some-state-when-a-prop-changes
  const [syncedTask, setSyncedTask] = useState(task);
  if (task !== syncedTask) {
    setSyncedTask(task);
    setLocal(task);
  }

  if (!task || !local) return null;

  function commit(patch: Partial<Task>) {
    if (!taskId) return;
    setLocal((prev) => (prev ? { ...prev, ...patch } : prev));
    void updateTask(taskId, patch);
  }

  return (
    <Sheet open={!!taskId} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="mx-auto max-h-[90vh] max-w-2xl overflow-y-auto rounded-t-2xl">
        <SheetHeader>
          <SheetTitle className="sr-only">{local.title}</SheetTitle>
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
              <Label>{t("dueDate")}</Label>
              <Popover>
                <PopoverTrigger render={<Button variant="outline" className="justify-start gap-2 font-normal" />}>
                  <CalendarIcon className="size-4" />
                  {local.due_at ? format(new Date(local.due_at), "d/M/yyyy") : "—"}
                </PopoverTrigger>
                <PopoverContent className="w-auto p-0">
                  <Calendar
                    mode="single"
                    selected={local.due_at ? new Date(local.due_at) : undefined}
                    onSelect={(date) => commit({ due_at: date ? date.toISOString() : null })}
                  />
                </PopoverContent>
              </Popover>
            </div>

            <div className="grid gap-2">
              <Label>{t("priority")}</Label>
              <Select value={String(local.priority ?? 0)} onValueChange={(v) => commit({ priority: Number(v) })}>
                <SelectTrigger>
                  <SelectValue>{(v: string) => PRIORITIES.find((p) => p.value === v)?.labelHe}</SelectValue>
                </SelectTrigger>
                <SelectContent>
                  {PRIORITIES.map((p) => (
                    <SelectItem key={p.value} value={p.value}>
                      {p.labelHe}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="grid gap-2">
              <Label>{t("assignee")}</Label>
              <AssigneeMultiSelect
                assigneeKind={local.assignee_kind}
                assigneeMemberIds={local.assignee_member_ids}
                onChange={(next) => commit(next)}
              />
            </div>

            <div className="grid gap-2">
              <Label>{t("doneBy")}</Label>
              <p className="flex h-8 items-center text-sm text-muted-foreground">
                {local.completed_by
                  ? `${members[local.completed_by]?.avatar_emoji ?? ""} ${members[local.completed_by]?.display_name ?? "?"}`
                  : "—"}
              </p>
            </div>
          </div>

          {sectionKind === "shopping" && (
            <div className="grid grid-cols-3 gap-3">
              <div className="grid gap-2">
                <Label>{t("quantity")}</Label>
                <Input
                  value={local.quantity ?? ""}
                  onChange={(e) => setLocal({ ...local, quantity: e.target.value === "" ? null : Number(e.target.value) })}
                  onBlur={(e) => commit({ quantity: e.target.value === "" ? null : Number(e.target.value) })}
                  type="number"
                />
              </div>
              <div className="grid gap-2">
                <Label>{t("price")}</Label>
                <Input
                  value={local.price ?? ""}
                  onChange={(e) => setLocal({ ...local, price: e.target.value === "" ? null : Number(e.target.value) })}
                  onBlur={(e) => commit({ price: e.target.value === "" ? null : Number(e.target.value) })}
                  type="number"
                />
              </div>
              <div className="grid gap-2">
                <Label>{t("brand")}</Label>
                <Input
                  dir="auto"
                  value={local.brand ?? ""}
                  onChange={(e) => setLocal({ ...local, brand: e.target.value })}
                  onBlur={(e) => commit({ brand: e.target.value || null })}
                />
              </div>
            </div>
          )}

          <div className="grid gap-2">
            <Label>{t("tags")}</Label>
            <div className="flex flex-wrap gap-1.5">
              {local.tags.map((tag) => (
                <Button
                  key={tag}
                  variant="secondary"
                  size="sm"
                  className="h-6 gap-1 rounded-full px-2 text-xs"
                  onClick={() => commit({ tags: local.tags.filter((tg) => tg !== tag) })}
                >
                  {tag}
                  <X className="size-3" />
                </Button>
              ))}
              <Input
                dir="auto"
                value={tagInput}
                onChange={(e) => setTagInput(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && tagInput.trim()) {
                    commit({ tags: [...new Set([...local.tags, tagInput.trim()])] });
                    setTagInput("");
                  }
                }}
                placeholder="#"
                className="h-6 w-20 border-none px-1 text-xs shadow-none"
              />
            </div>
          </div>

          <div className="grid gap-2">
            <Label>העברה לקטגוריה</Label>
            <Select value={local.section_id} onValueChange={(v) => v && commit({ section_id: v })}>
              <SelectTrigger>
                <SelectValue>{(v: string) => (sections[v] ? `${sections[v].emoji} ${sections[v].name}` : v)}</SelectValue>
              </SelectTrigger>
              <SelectContent>
                {Object.values(sections)
                  .filter((s) => !s.deleted_at)
                  .map((s) => (
                    <SelectItem key={s.id} value={s.id}>
                      {s.emoji} {s.name}
                    </SelectItem>
                  ))}
              </SelectContent>
            </Select>
          </div>
        </div>

        <SheetFooter className="flex-row justify-between border-t pt-4">
          <Button
            variant="destructive"
            size="sm"
            className="gap-2"
            onClick={() => {
              softDeleteTask(taskId!);
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

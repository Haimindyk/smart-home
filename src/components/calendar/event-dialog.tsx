"use client";

import { useState } from "react";
import { format } from "date-fns";
import { CalendarIcon, Trash2 } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useIdentity } from "@/lib/identity";
import { useT } from "@/lib/i18n/store";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Calendar } from "@/components/ui/calendar";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { EventKind, FamilyEvent } from "@/types/domain";

const KIND_EMOJI: Record<EventKind, string> = {
  birthday: "🎂",
  medical: "🏥",
  other: "📌",
};

export function EventDialog({
  open,
  onOpenChange,
  event,
  defaultDate,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  event: FamilyEvent | null;
  defaultDate?: Date;
}) {
  const createFamilyEvent = useAppStore((s) => s.createFamilyEvent);
  const updateFamilyEvent = useAppStore((s) => s.updateFamilyEvent);
  const deleteFamilyEvent = useAppStore((s) => s.deleteFamilyEvent);
  const actingMemberId = useIdentity((s) => s.actingMemberId);
  const t = useT();

  const [title, setTitle] = useState(event?.title ?? "");
  const [kind, setKind] = useState<EventKind>(event?.kind ?? "other");
  const [date, setDate] = useState<Date>(() => {
    if (event) return new Date(event.event_date);
    return defaultDate ?? new Date();
  });
  const [recurrence, setRecurrence] = useState<boolean>(event?.recurrence === "yearly");
  const [notes, setNotes] = useState(event?.notes ?? "");

  const [syncedEvent, setSyncedEvent] = useState(event);
  if (event !== syncedEvent) {
    setSyncedEvent(event);
    setTitle(event?.title ?? "");
    setKind(event?.kind ?? "other");
    setDate(event ? new Date(event.event_date) : (defaultDate ?? new Date()));
    setRecurrence(event?.recurrence === "yearly");
    setNotes(event?.notes ?? "");
  }

  function submit() {
    if (!title.trim()) return;
    const eventDate = format(date, "yyyy-MM-dd");
    if (event) {
      void updateFamilyEvent(event.id, {
        title: title.trim(),
        kind,
        event_date: eventDate,
        recurrence: recurrence ? "yearly" : "none",
        notes: notes.trim() || null,
        emoji: KIND_EMOJI[kind],
      });
    } else {
      void createFamilyEvent({
        title: title.trim(),
        kind,
        eventDate,
        recurrence: recurrence ? "yearly" : "none",
        notes: notes.trim() || null,
        emoji: KIND_EMOJI[kind],
        createdBy: actingMemberId,
      });
    }
    onOpenChange(false);
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{event ? t("editEvent") : t("addEvent")}</DialogTitle>
        </DialogHeader>
        <div className="flex flex-col gap-4 py-2">
          <div className="grid gap-2">
            <Label>{t("eventTitle")}</Label>
            <Input dir="auto" autoFocus value={title} onChange={(e) => setTitle(e.target.value)} />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="grid gap-2">
              <Label>{t("eventKind")}</Label>
              <Select value={kind} onValueChange={(v) => v && setKind(v as EventKind)}>
                <SelectTrigger>
                  <SelectValue>
                    {(v: EventKind) => `${KIND_EMOJI[v]} ${t(`kind_${v}` as const)}`}
                  </SelectValue>
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="birthday">{KIND_EMOJI.birthday} {t("kind_birthday")}</SelectItem>
                  <SelectItem value="medical">{KIND_EMOJI.medical} {t("kind_medical")}</SelectItem>
                  <SelectItem value="other">{KIND_EMOJI.other} {t("kind_other")}</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="grid gap-2">
              <Label>{t("eventDate")}</Label>
              <Popover>
                <PopoverTrigger render={<Button variant="outline" className="justify-start gap-2 font-normal" />}>
                  <CalendarIcon className="size-4" />
                  {format(date, "d/M/yyyy")}
                </PopoverTrigger>
                <PopoverContent className="w-auto p-0">
                  <Calendar mode="single" selected={date} onSelect={(d) => d && setDate(d)} />
                </PopoverContent>
              </Popover>
            </div>
          </div>

          <div className="flex items-center justify-between gap-3 rounded-lg border p-3">
            <Label className="font-normal">{t("repeatsYearly")}</Label>
            <Switch checked={recurrence} onCheckedChange={setRecurrence} />
          </div>

          <div className="grid gap-2">
            <Label>{t("eventNotes")}</Label>
            <Textarea dir="auto" value={notes} onChange={(e) => setNotes(e.target.value)} rows={2} />
          </div>
        </div>
        <DialogFooter className="flex-row items-center justify-between">
          {event ? (
            <Button
              variant="destructive"
              size="sm"
              className="gap-2"
              onClick={() => {
                void deleteFamilyEvent(event.id);
                onOpenChange(false);
              }}
            >
              <Trash2 className="size-4" />
              {t("delete")}
            </Button>
          ) : (
            <span />
          )}
          <Button onClick={submit} disabled={!title.trim()}>
            {event ? t("save") : t("addEvent")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

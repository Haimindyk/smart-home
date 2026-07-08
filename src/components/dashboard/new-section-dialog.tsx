"use client";

import { useState } from "react";
import { Plus } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useIdentity } from "@/lib/identity";
import { useT } from "@/lib/i18n/store";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
  DialogFooter,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { SectionKind } from "@/types/domain";

export function NewSectionDialog() {
  const createSection = useAppStore((s) => s.createSection);
  const actingMemberId = useIdentity((s) => s.actingMemberId);
  const t = useT();
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [emoji, setEmoji] = useState("");
  const [kind, setKind] = useState<SectionKind>("tasks");

  function submit() {
    if (!name.trim()) return;
    void createSection({ name: name.trim(), emoji: emoji || undefined, kind, createdBy: actingMemberId });
    setName("");
    setEmoji("");
    setKind("tasks");
    setOpen(false);
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button className="gap-2" />}>
        <Plus className="size-4" />
        {t("newSection")}
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("newSection")}</DialogTitle>
        </DialogHeader>
        <div className="flex flex-col gap-4 py-2">
          <div className="flex gap-2">
            <div className="grid gap-2">
              <Label>Emoji</Label>
              <Input value={emoji} onChange={(e) => setEmoji(e.target.value.slice(0, 4))} className="w-16 text-center" placeholder="✨" />
            </div>
            <div className="grid flex-1 gap-2">
              <Label>שם</Label>
              <Input dir="auto" value={name} onChange={(e) => setName(e.target.value)} onKeyDown={(e) => e.key === "Enter" && submit()} autoFocus />
            </div>
          </div>
          <div className="grid gap-2">
            <Label>סוג</Label>
            <Select value={kind} onValueChange={(v) => v && setKind(v as SectionKind)}>
              <SelectTrigger>
                <SelectValue>
                  {(v: SectionKind) =>
                    t(
                      v === "tasks"
                        ? "section_tasks"
                        : v === "shopping"
                          ? "section_shopping"
                          : v === "chores"
                            ? "section_chores"
                            : "section_info"
                    )
                  }
                </SelectValue>
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="tasks">{t("section_tasks")}</SelectItem>
                <SelectItem value="shopping">{t("section_shopping")}</SelectItem>
                <SelectItem value="chores">{t("section_chores")}</SelectItem>
                <SelectItem value="info">{t("section_info")}</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
        <DialogFooter>
          <Button onClick={submit} disabled={!name.trim()}>
            {t("newSection")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

"use client";

import { useEffect, useState } from "react";
import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { cn } from "@/lib/utils";

const EMOJI_OPTIONS = ["🙂", "🧑", "👤", "🧔", "👩", "🧑‍🦱", "🧑‍🦰", "👨", "🐶", "💙"];
const COLOR_OPTIONS = ["#6366f1", "#3b82f6", "#0ea5e9", "#10b981", "#f59e0b", "#ec4899", "#a855f7", "#ef4444"];

export function ProfileEditDialog({
  memberId,
  open,
  onOpenChange,
}: {
  memberId: string | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const member = useAppStore((s) => (memberId ? s.members[memberId] : undefined));
  const updateMember = useAppStore((s) => s.updateMember);
  const t = useT();

  const [name, setName] = useState("");
  const [emoji, setEmoji] = useState("🙂");
  const [color, setColor] = useState(COLOR_OPTIONS[0]);

  useEffect(() => {
    if (member) {
      setName(member.display_name);
      setEmoji(member.avatar_emoji ?? "🙂");
      setColor(member.color);
    }
  }, [member]);

  function save() {
    if (!memberId || !name.trim()) return;
    void updateMember(memberId, { display_name: name.trim(), avatar_emoji: emoji, color });
    onOpenChange(false);
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("myProfile")}</DialogTitle>
        </DialogHeader>
        <div className="flex flex-col gap-4 py-2">
          <div className="grid gap-2">
            <Label>{t("name")}</Label>
            <Input dir="auto" value={name} onChange={(e) => setName(e.target.value)} autoFocus />
          </div>

          <div className="grid gap-2">
            <Label>{t("avatar")}</Label>
            <div className="flex flex-wrap gap-1.5">
              {EMOJI_OPTIONS.map((e) => (
                <button
                  key={e}
                  type="button"
                  onClick={() => setEmoji(e)}
                  className={cn(
                    "flex size-9 items-center justify-center rounded-lg border text-lg transition-colors hover:bg-accent",
                    emoji === e && "border-primary bg-accent"
                  )}
                >
                  {e}
                </button>
              ))}
            </div>
          </div>

          <div className="grid gap-2">
            <Label>{t("color")}</Label>
            <div className="flex flex-wrap gap-1.5">
              {COLOR_OPTIONS.map((c) => (
                <button
                  key={c}
                  type="button"
                  onClick={() => setColor(c)}
                  style={{ backgroundColor: c }}
                  className={cn(
                    "size-8 rounded-full ring-offset-2 ring-offset-background transition-shadow",
                    color === c && "ring-2 ring-foreground"
                  )}
                  aria-label={c}
                />
              ))}
            </div>
          </div>

          <div
            className="flex items-center gap-2 rounded-lg border p-2.5"
            style={{ backgroundColor: `${color}15` }}
          >
            <span className="text-xl">{emoji}</span>
            <span dir="auto" className="text-sm font-medium" style={{ color }}>
              {name || "…"}
            </span>
          </div>
        </div>
        <DialogFooter>
          <Button onClick={save} disabled={!name.trim()}>
            {t("save")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

"use client";

import { useRef, useState } from "react";
import { Camera, X } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { createClient } from "@/lib/supabase/client";
import { useT } from "@/lib/i18n/store";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { MemberAvatar } from "@/components/identity/member-avatar";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { cn } from "@/lib/utils";
import { toast } from "sonner";

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
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);

  const [name, setName] = useState(() => member?.display_name ?? "");
  const [emoji, setEmoji] = useState(() => member?.avatar_emoji ?? "🙂");
  const [color, setColor] = useState(() => member?.color ?? COLOR_OPTIONS[0]);
  const [photoUrl, setPhotoUrl] = useState<string | null>(() => member?.avatar_photo_url ?? null);

  // Re-sync local edit state whenever the store's member reference changes
  // (opening the dialog for someone, or a realtime echo of our own save) —
  // adjusting state during render per
  // https://react.dev/learn/you-might-not-need-an-effect#adjusting-some-state-when-a-prop-changes
  const [syncedMember, setSyncedMember] = useState(member);
  if (member !== syncedMember) {
    setSyncedMember(member);
    if (member) {
      setName(member.display_name);
      setEmoji(member.avatar_emoji ?? "🙂");
      setColor(member.color);
      setPhotoUrl(member.avatar_photo_url ?? null);
    }
  }

  function save() {
    if (!memberId || !name.trim()) return;
    void updateMember(memberId, { display_name: name.trim(), avatar_emoji: emoji, color, avatar_photo_url: photoUrl });
    onOpenChange(false);
  }

  async function uploadPhoto(file: File) {
    if (!memberId) return;
    setUploading(true);
    try {
      const ext = file.name.split(".").pop()?.toLowerCase() || "jpg";
      const path = `${memberId}/${Date.now()}.${ext}`;
      const supabase = createClient();
      const { error } = await supabase.storage.from("avatars").upload(path, file, {
        upsert: true,
        contentType: file.type,
      });
      if (error) throw error;
      const { data } = supabase.storage.from("avatars").getPublicUrl(path);
      setPhotoUrl(data.publicUrl);
    } catch {
      toast.error("לא הצלחנו להעלות את התמונה");
    } finally {
      setUploading(false);
    }
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
            <Label>{t("profilePhoto")}</Label>
            <div className="flex items-center gap-3">
              <button
                type="button"
                onClick={() => fileInputRef.current?.click()}
                disabled={uploading}
                className="relative flex size-14 shrink-0 items-center justify-center overflow-hidden rounded-full border bg-accent/50 text-xl disabled:opacity-60"
              >
                {photoUrl ? (
                  <MemberAvatar member={{ avatar_photo_url: photoUrl }} className="size-14" />
                ) : (
                  <Camera className="size-5 text-muted-foreground" />
                )}
              </button>
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                className="hidden"
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  if (file) void uploadPhoto(file);
                  e.target.value = "";
                }}
              />
              <div className="flex flex-col gap-1">
                <Button type="button" variant="outline" size="sm" disabled={uploading} onClick={() => fileInputRef.current?.click()}>
                  {uploading ? "…" : t("uploadPhoto")}
                </Button>
                {photoUrl && (
                  <Button type="button" variant="ghost" size="sm" className="gap-1 text-muted-foreground" onClick={() => setPhotoUrl(null)}>
                    <X className="size-3.5" /> {t("removePhoto")}
                  </Button>
                )}
              </div>
            </div>
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
            <MemberAvatar member={{ avatar_photo_url: photoUrl, avatar_emoji: emoji }} className="size-6" emojiClassName="text-xl" />
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

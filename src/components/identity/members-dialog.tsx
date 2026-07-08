"use client";

import { useState } from "react";
import { Pencil, Plus, Share2, Copy } from "lucide-react";
import { useIdentity } from "@/lib/identity";
import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { MemberAvatar } from "@/components/identity/member-avatar";
import { ProfileEditDialog } from "@/components/identity/profile-edit-dialog";
import { EMOJI_OPTIONS, COLOR_OPTIONS } from "@/components/identity/avatar-options";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { cn } from "@/lib/utils";
import { toast } from "sonner";
import type { Member } from "@/types/domain";

type Mode = "list" | "add" | { share: Member; pin: string };

export function MembersDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  const actingMemberId = useIdentity((s) => s.actingMemberId);
  const members = useAppStore((s) => s.members);
  const addMember = useAppStore((s) => s.addMember);
  const t = useT();

  const [mode, setMode] = useState<Mode>("list");
  const [editingMemberId, setEditingMemberId] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [pin, setPin] = useState("");
  const [emoji, setEmoji] = useState(EMOJI_OPTIONS[0]);
  const [color, setColor] = useState(COLOR_OPTIONS[0]);
  const [pinError, setPinError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const memberList = Object.values(members).sort((a, b) => a.display_name.localeCompare(b.display_name));

  function resetForm() {
    setName("");
    setPin("");
    setEmoji(EMOJI_OPTIONS[0]);
    setColor(COLOR_OPTIONS[0]);
    setPinError(null);
  }

  function close() {
    onOpenChange(false);
    setMode("list");
    resetForm();
  }

  async function submitAdd() {
    if (!name.trim() || !/^\d{4}$/.test(pin)) return;
    setSaving(true);
    setPinError(null);
    const result = await addMember({ displayName: name.trim(), pin, avatarEmoji: emoji, color });
    setSaving(false);
    if ("error" in result) {
      setPinError(t("pinTaken"));
      return;
    }
    setMode({ share: result.member, pin });
    resetForm();
  }

  function shareText(member: Member, memberPin: string) {
    const url = typeof window !== "undefined" ? window.location.origin : "";
    return t("shareInviteMessage")
      .replace("{name}", member.display_name)
      .replace("{appName}", t("appName"))
      .replace("{url}", url)
      .replace("{pin}", memberPin);
  }

  async function share(member: Member, memberPin: string) {
    const text = shareText(member, memberPin);
    if (typeof navigator !== "undefined" && navigator.share) {
      try {
        await navigator.share({ text, title: t("appName") });
        return;
      } catch {
        // user cancelled the share sheet — fall through to nothing
        return;
      }
    }
    await navigator.clipboard.writeText(text);
    toast.success(t("linkCopied"));
  }

  return (
    <>
      <Dialog
        open={open}
        onOpenChange={(next) => {
          if (!next) close();
          else onOpenChange(true);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {typeof mode === "object" ? t("memberAdded") : mode === "add" ? t("addMember") : t("householdMembers")}
            </DialogTitle>
          </DialogHeader>

          {mode === "list" && (
            <div className="flex flex-col gap-4 py-2">
              <div className="flex flex-col gap-1.5">
                {memberList.map((m) => (
                  <div key={m.id} className="flex items-center gap-3 rounded-lg border p-2.5">
                    <MemberAvatar member={m} className="size-10" emojiClassName="text-2xl" />
                    <div className="flex min-w-0 flex-1 items-center gap-1.5">
                      <span dir="auto" className="truncate text-sm font-medium">
                        {m.display_name}
                      </span>
                      {m.id === actingMemberId && (
                        <span className="shrink-0 text-xs text-muted-foreground">{t("youLabel")}</span>
                      )}
                    </div>
                    {m.id === actingMemberId && (
                      <Button
                        type="button"
                        variant="ghost"
                        size="icon"
                        className="shrink-0"
                        onClick={() => setEditingMemberId(m.id)}
                        aria-label={t("editProfile")}
                      >
                        <Pencil className="size-4" />
                      </Button>
                    )}
                  </div>
                ))}
              </div>

              <Button type="button" variant="outline" className="gap-1.5" onClick={() => setMode("add")}>
                <Plus className="size-4" /> {t("addMember")}
              </Button>
            </div>
          )}

          {mode === "add" && (
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

              <div className="grid gap-2">
                <Label>{t("initialPin")}</Label>
                <Input
                  dir="ltr"
                  inputMode="numeric"
                  maxLength={4}
                  placeholder="0000"
                  value={pin}
                  onChange={(e) => {
                    setPin(e.target.value.replace(/\D/g, "").slice(0, 4));
                    setPinError(null);
                  }}
                  className="text-center tracking-[0.4em]"
                />
                <span className="text-xs text-muted-foreground">{pinError ?? t("pinFourDigits")}</span>
              </div>

              <DialogFooter>
                <Button
                  onClick={submitAdd}
                  disabled={saving || !name.trim() || !/^\d{4}$/.test(pin)}
                >
                  {t("add")}
                </Button>
              </DialogFooter>
            </div>
          )}

          {typeof mode === "object" && (
            <div className="flex flex-col gap-4 py-2">
              <div
                className="flex items-center gap-2 rounded-lg border p-2.5"
                style={{ backgroundColor: `${mode.share.color}15` }}
              >
                <MemberAvatar member={mode.share} className="size-8" emojiClassName="text-2xl" />
                <span dir="auto" className="text-sm font-medium" style={{ color: mode.share.color }}>
                  {mode.share.display_name}
                </span>
              </div>

              <p className="text-sm text-muted-foreground">
                {t("shareInviteIntro").replace("{name}", mode.share.display_name)}
              </p>

              <div className="flex flex-col gap-2">
                <Button type="button" className="gap-1.5" onClick={() => void share(mode.share, mode.pin)}>
                  <Share2 className="size-4" /> {t("shareLink")}
                </Button>
                <Button
                  type="button"
                  variant="outline"
                  className="gap-1.5"
                  onClick={async () => {
                    await navigator.clipboard.writeText(shareText(mode.share, mode.pin));
                    toast.success(t("linkCopied"));
                  }}
                >
                  <Copy className="size-4" /> {t("copyLink")}
                </Button>
              </div>

              <DialogFooter>
                <Button variant="ghost" onClick={() => setMode("list")}>
                  {t("done")}
                </Button>
              </DialogFooter>
            </div>
          )}
        </DialogContent>
      </Dialog>

      <ProfileEditDialog
        memberId={editingMemberId}
        open={!!editingMemberId}
        onOpenChange={(next) => !next && setEditingMemberId(null)}
      />
    </>
  );
}

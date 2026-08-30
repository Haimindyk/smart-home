"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Plus } from "lucide-react";
import { useIdentity } from "@/lib/identity";
import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { MemberAvatar } from "@/components/identity/member-avatar";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { cn } from "@/lib/utils";

type Mode = "list" | "create";

/** Lists the private boards this device's signed-in member is on (see
 * migration 0034) and lets them create a new one with whichever household
 * members they pick — the list itself is already the correct set: RLS only
 * ever hands this member their own boards, so there's nothing to filter
 * here client-side. */
export function BoardsDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  const router = useRouter();
  const actingMemberId = useIdentity((s) => s.actingMemberId);
  const members = useAppStore((s) => s.members);
  const boards = useAppStore((s) => s.boards);
  const boardMembers = useAppStore((s) => s.boardMembers);
  const createBoard = useAppStore((s) => s.createBoard);
  const t = useT();

  const [mode, setMode] = useState<Mode>("list");
  const [name, setName] = useState("");
  const [emoji, setEmoji] = useState("");
  const [pickedIds, setPickedIds] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);

  const boardList = Object.values(boards).sort((a, b) => a.name.localeCompare(b.name));
  const otherMembers = Object.values(members)
    .filter((m) => m.id !== actingMemberId)
    .sort((a, b) => a.display_name.localeCompare(b.display_name));

  function membersOf(boardId: string) {
    return Object.values(boardMembers)
      .filter((bm) => bm.board_id === boardId)
      .map((bm) => members[bm.member_id])
      .filter((m): m is NonNullable<typeof m> => !!m);
  }

  function close() {
    onOpenChange(false);
    setMode("list");
    setName("");
    setEmoji("");
    setPickedIds([]);
  }

  function openBoard(boardId: string) {
    close();
    router.push(`/boards/${boardId}`);
  }

  async function submitCreate() {
    if (!name.trim()) return;
    setSaving(true);
    const boardId = await createBoard({ name: name.trim(), emoji: emoji || null, memberIds: pickedIds });
    setSaving(false);
    if (boardId) openBoard(boardId);
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        if (!next) close();
        else onOpenChange(true);
      }}
    >
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{mode === "create" ? t("newBoard") : t("boards")}</DialogTitle>
        </DialogHeader>

        {mode === "list" && (
          <div className="flex flex-col gap-4 py-2">
            {boardList.length === 0 ? (
              <p className="py-4 text-center text-sm text-muted-foreground">{t("noBoardsYet")}</p>
            ) : (
              <div className="flex flex-col gap-1.5">
                {boardList.map((b) => (
                  <button
                    key={b.id}
                    type="button"
                    onClick={() => openBoard(b.id)}
                    className="flex items-center gap-3 rounded-lg border p-2.5 text-start transition-colors hover:bg-accent/50"
                  >
                    <span className="text-2xl">{b.emoji || "🔒"}</span>
                    <div className="flex min-w-0 flex-1 flex-col">
                      <span dir="auto" className="truncate text-sm font-medium">
                        {b.name}
                      </span>
                      <div className="flex -space-x-1.5 rtl:space-x-reverse">
                        {membersOf(b.id).map((m) => (
                          <MemberAvatar key={m.id} member={m} className="size-5 ring-2 ring-background" emojiClassName="text-xs" />
                        ))}
                      </div>
                    </div>
                  </button>
                ))}
              </div>
            )}

            <Button type="button" variant="outline" className="gap-1.5" onClick={() => setMode("create")}>
              <Plus className="size-4" /> {t("newBoard")}
            </Button>
          </div>
        )}

        {mode === "create" && (
          <div className="flex flex-col gap-4 py-2">
            <div className="flex gap-2">
              <div className="grid gap-2">
                <Label>{t("emoji")}</Label>
                <Input value={emoji} onChange={(e) => setEmoji(e.target.value.slice(0, 4))} className="w-16 text-center" placeholder="🔒" />
              </div>
              <div className="grid flex-1 gap-2">
                <Label>{t("boardName")}</Label>
                <Input dir="auto" value={name} onChange={(e) => setName(e.target.value)} autoFocus />
              </div>
            </div>

            <div className="grid gap-2">
              <Label>{t("boardMembersLabel")}</Label>
              <div className="flex flex-col gap-1.5">
                {otherMembers.map((m) => {
                  const picked = pickedIds.includes(m.id);
                  return (
                    <button
                      key={m.id}
                      type="button"
                      onClick={() =>
                        setPickedIds((ids) => (picked ? ids.filter((id) => id !== m.id) : [...ids, m.id]))
                      }
                      className={cn(
                        "flex items-center gap-2.5 rounded-lg border p-2 text-start transition-colors",
                        picked ? "border-primary bg-primary/5" : "hover:bg-accent/50"
                      )}
                    >
                      <MemberAvatar member={m} className="size-8" />
                      <span dir="auto" className="flex-1 text-sm font-medium">
                        {m.display_name}
                      </span>
                      <span
                        className={cn(
                          "flex size-5 items-center justify-center rounded-full border-2",
                          picked ? "border-primary bg-primary" : "border-muted-foreground/30"
                        )}
                      />
                    </button>
                  );
                })}
              </div>
            </div>

            <DialogFooter>
              <Button onClick={submitCreate} disabled={saving || !name.trim()}>
                {t("createBoard")}
              </Button>
            </DialogFooter>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

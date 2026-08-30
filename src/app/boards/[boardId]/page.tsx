"use client";

import { useMemo } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import { Loader2 } from "lucide-react";
import { AppHeader } from "@/components/nav/app-header";
import { CategoryTabs } from "@/components/dashboard/category-tabs";
import { SectionPanels } from "@/components/dashboard/section-panels";
import { NewSectionDialog } from "@/components/dashboard/new-section-dialog";
import { MemberAvatar } from "@/components/identity/member-avatar";
import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import { sortByPosition } from "@/lib/ordering/rank";

export default function BoardPage() {
  const params = useParams<{ boardId: string }>();
  const boardId = params.boardId;
  const t = useT();

  const board = useAppStore((s) => s.boards[boardId]);
  const boardMembers = useAppStore((s) => s.boardMembers);
  const members = useAppStore((s) => s.members);
  const sectionsById = useAppStore((s) => s.sections);
  const hydrated = useAppStore((s) => s.hydrated);

  const sections = useMemo(
    () => sortByPosition(Object.values(sectionsById).filter((s) => !s.deleted_at && s.board_id === boardId)),
    [sectionsById, boardId]
  );

  const memberList = useMemo(
    () =>
      Object.values(boardMembers)
        .filter((bm) => bm.board_id === boardId)
        .map((bm) => members[bm.member_id])
        .filter((m): m is NonNullable<typeof m> => !!m),
    [boardMembers, members, boardId]
  );

  return (
    <div className="flex min-h-full flex-1 flex-col">
      <AppHeader />
      <main className="mx-auto w-full max-w-3xl flex-1 px-4 py-6">
        {!hydrated ? (
          <div className="glass surface-shadow flex flex-col items-center gap-3 rounded-3xl p-12 text-center ring-1 ring-border/40">
            <Loader2 className="size-8 animate-spin text-primary" />
            <p className="text-muted-foreground">{t("loadingApp")}</p>
          </div>
        ) : !board ? (
          // RLS (migration 0034) simply omits a board's rows entirely for
          // anyone not on it — this state covers both "no such board" and
          // "not your board", indistinguishably, which is exactly the
          // point: existence itself is private.
          <div className="glass surface-shadow flex flex-col items-center gap-3 rounded-3xl p-12 text-center ring-1 ring-border/40">
            <span className="text-4xl">🔒</span>
            <p className="text-muted-foreground">{t("noBoardsYet")}</p>
            <Link href="/" className="text-sm text-primary underline underline-offset-4">
              {t("backToHome")}
            </Link>
          </div>
        ) : (
          <>
            <div
              className="glass surface-shadow relative mb-4 overflow-hidden rounded-3xl p-6 ring-1 ring-border/40 sm:p-8"
              style={{
                backgroundImage:
                  "radial-gradient(140% 100% at 100% -10%, color-mix(in oklch, var(--primary) 18%, transparent), transparent 60%)",
              }}
            >
              <div className="flex flex-wrap items-end justify-between gap-4">
                <div>
                  <Link href="/" className="eyebrow mb-2 inline-block hover:underline">
                    {t("backToHome")}
                  </Link>
                  <p className="flex items-center gap-2 text-2xl font-bold tracking-tight text-balance sm:text-3xl">
                    <span>{board.emoji || "🔒"}</span>
                    <span dir="auto">{board.name}</span>
                  </p>
                  <div className="mt-2 flex -space-x-1.5 rtl:space-x-reverse">
                    {memberList.map((m) => (
                      <MemberAvatar key={m.id} member={m} className="size-6 ring-2 ring-background" emojiClassName="text-sm" />
                    ))}
                  </div>
                </div>
                <NewSectionDialog boardId={boardId} />
              </div>
            </div>

            {sections.length > 0 ? (
              <>
                <CategoryTabs sections={sections} />
                <SectionPanels sections={sections} />
              </>
            ) : (
              <div className="glass surface-shadow flex flex-col items-center gap-3 rounded-3xl p-12 text-center ring-1 ring-border/40">
                <span className="text-4xl">🔒</span>
                <p className="text-muted-foreground">{t("noTasksYet")}</p>
                <NewSectionDialog boardId={boardId} />
              </div>
            )}
          </>
        )}
      </main>
    </div>
  );
}

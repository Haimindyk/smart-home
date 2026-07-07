"use client";

import { useMemo } from "react";
import { useAppStore } from "@/lib/store/app-store";
import { useIdentity } from "@/lib/identity";
import { useT } from "@/lib/i18n/store";
import { sortByPosition } from "@/lib/ordering/rank";
import { AppHeader } from "@/components/nav/app-header";
import { ChoreRow } from "@/components/chores/chore-row";
import { ChoreQuickAdd } from "@/components/chores/chore-quick-add";

export default function ChoresPage() {
  const sections = useAppStore((s) => s.sections);
  const chores = useAppStore((s) => s.chores);
  const actingMemberId = useIdentity((s) => s.actingMemberId);
  const t = useT();

  const choreSections = useMemo(
    () => sortByPosition(Object.values(sections).filter((s) => s.kind === "chores" && !s.deleted_at)),
    [sections]
  );

  return (
    <div className="flex min-h-full flex-1 flex-col">
      <AppHeader />
      <main className="mx-auto w-full max-w-2xl flex-1 px-4 py-6">
        <h1 className="mb-1 text-2xl font-bold">{t("chores")}</h1>
        {!actingMemberId && <p className="mb-4 text-sm text-muted-foreground">{t("whoAreYouSubtitle")}</p>}

        {choreSections.map((section) => {
          const items = sortByPosition(
            Object.values(chores).filter((c) => c.section_id === section.id && !c.deleted_at)
          );
          const due = items.filter((c) => new Date(c.next_due_at).getTime() <= Date.now());
          const notDue = items.filter((c) => new Date(c.next_due_at).getTime() > Date.now());

          return (
            <section key={section.id} className="mb-6">
              <ChoreQuickAdd sectionId={section.id} />
              <div className="flex flex-col gap-2">
                {due.map((chore) => (
                  <ChoreRow key={chore.id} chore={chore} />
                ))}
                {notDue.map((chore) => (
                  <ChoreRow key={chore.id} chore={chore} />
                ))}
              </div>
            </section>
          );
        })}

        {choreSections.length === 0 && <p className="text-sm text-muted-foreground">{t("noTasksYet")}</p>}
      </main>
    </div>
  );
}

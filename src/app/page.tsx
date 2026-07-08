"use client";

import { useMemo } from "react";
import { AppHeader } from "@/components/nav/app-header";
import { CategoryTabs } from "@/components/dashboard/category-tabs";
import { SectionPanels } from "@/components/dashboard/section-panels";
import { NewSectionDialog } from "@/components/dashboard/new-section-dialog";
import { useAppStore } from "@/lib/store/app-store";
import { useIdentity } from "@/lib/identity";
import { useLocaleStore, useT } from "@/lib/i18n/store";
import { sortByPosition } from "@/lib/ordering/rank";

const GREETINGS = {
  he: { morning: "בוקר טוב", afternoon: "צהריים טובים", evening: "ערב טוב", night: "לילה טוב" },
  en: { morning: "Good morning", afternoon: "Good afternoon", evening: "Good evening", night: "Good night" },
} as const;

function useGreeting() {
  const locale = useLocaleStore((s) => s.locale);
  return useMemo(() => {
    const hour = new Date().getHours();
    const key = hour < 5 ? "night" : hour < 12 ? "morning" : hour < 18 ? "afternoon" : hour < 22 ? "evening" : "night";
    return GREETINGS[locale][key];
  }, [locale]);
}

export default function DashboardPage() {
  const t = useT();
  const greeting = useGreeting();
  const actingMemberId = useIdentity((s) => s.actingMemberId);
  const members = useAppStore((s) => s.members);
  const sectionsById = useAppStore((s) => s.sections);
  const me = actingMemberId ? members[actingMemberId] : undefined;

  const sections = useMemo(
    () => sortByPosition(Object.values(sectionsById).filter((s) => !s.deleted_at)),
    [sectionsById]
  );

  return (
    <div className="flex min-h-full flex-1 flex-col">
      <AppHeader />
      <main className="mx-auto w-full max-w-3xl flex-1 px-4 py-6">
        <div className="glass surface-shadow relative mb-4 overflow-hidden rounded-3xl p-6 ring-1 ring-border/40 sm:p-8">
          <div className="pointer-events-none absolute -end-16 -top-16 size-56 rounded-full bg-gradient-to-br from-indigo-400/30 to-violet-500/20 blur-3xl" />
          <div className="relative flex flex-wrap items-end justify-between gap-4">
            <div>
              <p className="text-sm text-muted-foreground">
                {greeting}
                {me ? `, ${me.display_name}` : ""} {me?.avatar_emoji}
              </p>
            </div>
            <NewSectionDialog />
          </div>
        </div>

        {sections.length > 0 ? (
          <>
            <CategoryTabs sections={sections} />
            <SectionPanels sections={sections} />
          </>
        ) : (
          <div className="glass surface-shadow flex flex-col items-center gap-3 rounded-3xl p-12 text-center ring-1 ring-border/40">
            <span className="text-4xl">💙</span>
            <p className="text-muted-foreground">{t("noTasksYet")}</p>
            <NewSectionDialog />
          </div>
        )}
      </main>
    </div>
  );
}

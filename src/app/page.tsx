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
          <div className="pointer-events-none absolute -end-20 -top-20 size-64 rounded-full bg-gradient-to-br from-indigo-400/40 to-violet-500/30 blur-3xl" />
          <div className="pointer-events-none absolute -start-16 -bottom-24 size-48 rounded-full bg-gradient-to-br from-sky-400/20 to-emerald-400/10 blur-3xl" />
          <div className="relative flex flex-wrap items-end justify-between gap-4">
            <div>
              <span className="eyebrow mb-2">{t("appName")}</span>
              <p className="text-2xl font-bold tracking-tight text-balance sm:text-3xl">
                {greeting}
                {me ? (
                  <>
                    {", "}
                    <span className="bg-gradient-to-br from-indigo-500 to-violet-600 bg-clip-text text-transparent">
                      {me.display_name}
                    </span>
                  </>
                ) : (
                  ""
                )}{" "}
                {me?.avatar_emoji}
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

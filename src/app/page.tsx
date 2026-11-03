"use client";

import Link from "next/link";
import { useHealthText } from "@/lib/health/i18n";
import { Leaf, ArrowUpLeft, Dumbbell } from "lucide-react";
import { useMemo } from "react";
import { Loader2 } from "lucide-react";
import { AppHeader } from "@/components/nav/app-header";
import { CategoryTabs } from "@/components/dashboard/category-tabs";
import { SectionPanels } from "@/components/dashboard/section-panels";
import { NewSectionDialog } from "@/components/dashboard/new-section-dialog";
import { InsightCards } from "@/components/assistant/insight-card";
import { PersonalNoteCards } from "@/components/assistant/personal-note-card";
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
  const h = useHealthText();
  const t = useT();
  const greeting = useGreeting();
  const actingMemberId = useIdentity((s) => s.actingMemberId);
  const members = useAppStore((s) => s.members);
  const sectionsById = useAppStore((s) => s.sections);
  const hydrated = useAppStore((s) => s.hydrated);
  const me = actingMemberId ? members[actingMemberId] : undefined;

  const sections = useMemo(
    () => sortByPosition(Object.values(sectionsById).filter((s) => !s.deleted_at)),
    [sectionsById]
  );

  return (
    <div className="flex min-h-full flex-1 flex-col">
      <AppHeader />
      <main className="mx-auto w-full max-w-3xl flex-1 px-4 py-6">
        <div
          className="glass surface-shadow relative mb-4 overflow-hidden rounded-3xl p-6 ring-1 ring-border/40 sm:p-8"
          style={{
            // A plain background-image instead of a separate blurred, absolutely-
            // positioned child — combining `backdrop-blur` (the `.glass` class)
            // with a sibling `blur-*` filter inside an `overflow-hidden` box
            // renders as a hard-edged rectangle on WebKit instead of a soft glow.
            backgroundImage:
              "radial-gradient(140% 100% at 100% -10%, color-mix(in oklch, var(--primary) 18%, transparent), transparent 60%)",
          }}
        >
          <div className="flex flex-wrap items-end justify-between gap-4">
            <div>
              <span className="eyebrow mb-2">{t("appName")}</span>
              <p className="text-2xl font-bold tracking-tight text-balance sm:text-3xl">
                {greeting}
                {me ? (
                  <>
                    {", "}
                    <span className="text-primary">{me.display_name}</span>
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

        <Link href="/health" className="group relative mb-6 flex min-h-40 items-center justify-between gap-5 overflow-hidden rounded-[28px] bg-[#151515] p-6 text-white shadow-lg transition duration-300 hover:-translate-y-1 hover:shadow-xl sm:p-8">
          <div className="relative z-10"><p className="mb-2 text-xs font-semibold tracking-[.2em] text-[#ffb623]">KH WELLNESS</p><h2 className="text-2xl font-bold sm:text-3xl">{h("זמן לעצמך", "Time for you")}</h2><p className="mt-2 text-sm text-white/65">{h("התזונה, האימונים וההתקדמות שלך", "Your nutrition, training & progress")}</p><span className="mt-4 inline-flex items-center gap-2 text-sm font-semibold text-[#ffb623]">{h("כניסה למרחב האישי", "Open your wellness space")}<ArrowUpLeft size={16}/></span></div>
          <div aria-hidden="true" className="relative flex size-24 shrink-0 items-center justify-center rounded-full border border-[#ffb623]/25 bg-[#ffb623]/10"><Leaf size={40} className="text-[#ffb623]"/><span className="absolute -bottom-1 -start-2 rounded-2xl bg-[#ffb623] p-2.5 text-[#151515]"><Dumbbell size={22}/></span></div>
        </Link>
        <PersonalNoteCards />
        <InsightCards />

        {!hydrated ? (
          <div className="glass surface-shadow flex flex-col items-center gap-3 rounded-3xl p-12 text-center ring-1 ring-border/40">
            <Loader2 className="size-8 animate-spin text-primary" />
            <p className="text-muted-foreground">{t("loadingApp")}</p>
          </div>
        ) : sections.length > 0 ? (
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

"use client";

import { AppHeader } from "@/components/nav/app-header";
import { DashboardGrid } from "@/components/dashboard/dashboard-grid";
import { NewSectionDialog } from "@/components/dashboard/new-section-dialog";
import { useT } from "@/lib/i18n/store";

export default function DashboardPage() {
  const t = useT();

  return (
    <div className="flex min-h-full flex-1 flex-col">
      <AppHeader />
      <main className="mx-auto w-full max-w-5xl flex-1 px-4 py-6">
        <div className="mb-5 flex items-center justify-between">
          <h1 className="text-2xl font-bold">{t("dashboard")}</h1>
          <NewSectionDialog />
        </div>
        <DashboardGrid />
      </main>
    </div>
  );
}

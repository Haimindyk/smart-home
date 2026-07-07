"use client";

import { useEffect } from "react";
import { ThemeProvider } from "next-themes";
import { TooltipProvider } from "@/components/ui/tooltip";
import { Toaster } from "@/components/ui/sonner";
import { useLocaleStore, dirFor } from "@/lib/i18n/store";
import { useRealtimeSync } from "@/lib/realtime/use-realtime-sync";
import { IdentityGate } from "@/components/identity/identity-gate";
import { OfflineBanner } from "@/components/common/offline-banner";
import { GlobalSearch } from "@/components/search/global-search";

function DirSync() {
  const locale = useLocaleStore((s) => s.locale);
  useEffect(() => {
    document.documentElement.dir = dirFor(locale);
    document.documentElement.lang = locale;
  }, [locale]);
  return null;
}

function DataBoot({ children }: { children: React.ReactNode }) {
  useRealtimeSync();
  return <>{children}</>;
}

export function AppProviders({ children }: { children: React.ReactNode }) {
  return (
    <ThemeProvider attribute="class" defaultTheme="system" enableSystem disableTransitionOnChange>
      <TooltipProvider>
        <DirSync />
        <DataBoot>
          <IdentityGate>
            <OfflineBanner />
            {children}
            <GlobalSearch />
          </IdentityGate>
        </DataBoot>
        <Toaster position="top-center" richColors />
      </TooltipProvider>
    </ThemeProvider>
  );
}

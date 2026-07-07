"use client";

import Link from "next/link";
import { Search, Moon, Sun, Laptop, Download, Users } from "lucide-react";
import { useTheme } from "next-themes";
import { useIdentity } from "@/lib/identity";
import { useAppStore } from "@/lib/store/app-store";
import { useSearchOpen } from "@/lib/search-ui-state";
import { useLocaleStore, useT } from "@/lib/i18n/store";
import { useInstallPrompt } from "@/lib/pwa/use-install-prompt";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

export function AppHeader() {
  const setSearchOpen = useSearchOpen((s) => s.setOpen);
  const { theme, setTheme } = useTheme();
  const locale = useLocaleStore((s) => s.locale);
  const setLocale = useLocaleStore((s) => s.setLocale);
  const actingMemberId = useIdentity((s) => s.actingMemberId);
  const setActingMemberId = useIdentity((s) => s.setActingMemberId);
  const members = useAppStore((s) => s.members);
  const t = useT();
  const { canInstall, promptInstall } = useInstallPrompt();

  const me = actingMemberId ? members[actingMemberId] : undefined;

  return (
    <header className="sticky top-0 z-40 flex items-center gap-3 border-b bg-background/80 px-4 py-3 backdrop-blur-md">
      <Link href="/" className="flex items-center gap-2 text-lg font-bold">
        <span className="text-xl">💙</span>
        {t("appName")}
      </Link>
      <nav className="flex items-center gap-1 text-sm">
        <Link href="/" className="rounded-md px-2 py-1 text-muted-foreground hover:bg-accent hover:text-foreground">
          {t("dashboard")}
        </Link>
        <Link href="/chores" className="rounded-md px-2 py-1 text-muted-foreground hover:bg-accent hover:text-foreground">
          {t("chores")}
        </Link>
      </nav>

      <div className="ms-auto flex items-center gap-1">
        {canInstall && (
          <Button variant="ghost" size="icon" onClick={promptInstall} aria-label={t("installApp")} title={t("installApp")}>
            <Download className="size-4" />
          </Button>
        )}
        <Button variant="ghost" size="icon" onClick={() => setSearchOpen(true)} aria-label={t("search")}>
          <Search className="size-4" />
        </Button>

        <DropdownMenu>
          <DropdownMenuTrigger render={<Button variant="ghost" className="gap-2 px-2" aria-label={t("changeIdentity")} />}>
            {me ? (
              <>
                <span>{me.avatar_emoji}</span>
                <span className="hidden sm:inline">{me.display_name}</span>
              </>
            ) : (
              <Users className="size-4" />
            )}
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-56">
            <DropdownMenuLabel>{t("changeIdentity")}</DropdownMenuLabel>
            {Object.values(members).map((m) => (
              <DropdownMenuItem key={m.id} onClick={() => setActingMemberId(m.id)}>
                {m.avatar_emoji} {m.display_name}
              </DropdownMenuItem>
            ))}
            <DropdownMenuItem onClick={() => setActingMemberId(null)}>{t("guest")}</DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuLabel>{t("language")}</DropdownMenuLabel>
            <DropdownMenuItem onClick={() => setLocale("he")}>{locale === "he" ? "✓ " : ""}עברית</DropdownMenuItem>
            <DropdownMenuItem onClick={() => setLocale("en")}>{locale === "en" ? "✓ " : ""}English</DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuLabel>{t("theme")}</DropdownMenuLabel>
            <DropdownMenuItem onClick={() => setTheme("light")}>
              <Sun className="size-4" /> {t("light")} {theme === "light" ? "✓" : ""}
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => setTheme("dark")}>
              <Moon className="size-4" /> {t("dark")} {theme === "dark" ? "✓" : ""}
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => setTheme("system")}>
              <Laptop className="size-4" /> {t("system")} {theme === "system" ? "✓" : ""}
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </header>
  );
}

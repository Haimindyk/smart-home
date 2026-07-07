"use client";

import { useState } from "react";
import Link from "next/link";
import { Search, Moon, Sun, Laptop, Download, Users, Pencil, History } from "lucide-react";
import { useTheme } from "next-themes";
import { useIdentity } from "@/lib/identity";
import { useAppStore } from "@/lib/store/app-store";
import { useSearchOpen } from "@/lib/search-ui-state";
import { useLocaleStore, useT } from "@/lib/i18n/store";
import { useInstallPrompt } from "@/lib/pwa/use-install-prompt";
import { Button } from "@/components/ui/button";
import { ProfileEditDialog } from "@/components/identity/profile-edit-dialog";
import { HistoryDialog } from "@/components/history/history-dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
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
  const members = useAppStore((s) => s.members);
  const t = useT();
  const { canInstall, promptInstall } = useInstallPrompt();
  const [profileOpen, setProfileOpen] = useState(false);
  const [historyOpen, setHistoryOpen] = useState(false);

  const me = actingMemberId ? members[actingMemberId] : undefined;

  return (
    <header className="glass sticky top-0 z-40 flex items-center gap-3 px-4 py-3 shadow-xs supports-backdrop-filter:shadow-none">
      <Link href="/" className="flex items-center gap-2 text-lg font-bold">
        <span className="bg-gradient-to-br from-indigo-500 to-violet-600 bg-clip-text text-xl text-transparent">💙</span>
        <span className="bg-gradient-to-br from-foreground to-foreground/70 bg-clip-text text-transparent">{t("appName")}</span>
      </Link>

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
          <DropdownMenuTrigger render={<Button variant="ghost" className="gap-2 px-2" aria-label={t("settings")} />}>
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
            <DropdownMenuGroup>
              {me && (
                <DropdownMenuItem onClick={() => setProfileOpen(true)}>
                  <Pencil className="size-4" /> {t("editProfile")}
                </DropdownMenuItem>
              )}
              <DropdownMenuItem onClick={() => setHistoryOpen(true)}>
                <History className="size-4" /> {t("history")}
              </DropdownMenuItem>
            </DropdownMenuGroup>
            <DropdownMenuSeparator />
            <DropdownMenuGroup>
              <DropdownMenuLabel>{t("language")}</DropdownMenuLabel>
              <DropdownMenuItem onClick={() => setLocale("he")}>{locale === "he" ? "✓ " : ""}עברית</DropdownMenuItem>
              <DropdownMenuItem onClick={() => setLocale("en")}>{locale === "en" ? "✓ " : ""}English</DropdownMenuItem>
            </DropdownMenuGroup>
            <DropdownMenuSeparator />
            <DropdownMenuGroup>
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
            </DropdownMenuGroup>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      <ProfileEditDialog memberId={actingMemberId} open={profileOpen} onOpenChange={setProfileOpen} />
      <HistoryDialog open={historyOpen} onOpenChange={setHistoryOpen} />
    </header>
  );
}

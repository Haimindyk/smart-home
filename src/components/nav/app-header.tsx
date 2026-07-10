"use client";

import { useState } from "react";
import Link from "next/link";
import { Search, Moon, Sun, Laptop, Users, Pencil, History, Bell, Check, ChevronDown, CalendarDays, Megaphone, ScanBarcode, Bot, MoreHorizontal } from "lucide-react";
import { useTheme } from "next-themes";
import { useIdentity } from "@/lib/identity";
import { useAppStore } from "@/lib/store/app-store";
import { useSearchOpen } from "@/lib/search-ui-state";
import { useAssistantOpen } from "@/lib/assistant-ui-state";
import { useLocaleStore, useT } from "@/lib/i18n/store";
import { Button } from "@/components/ui/button";
import { OfflineBanner } from "@/components/common/offline-banner";
import { ProfileEditDialog } from "@/components/identity/profile-edit-dialog";
import { HistoryDialog } from "@/components/history/history-dialog";
import { NotificationSettingsDialog } from "@/components/push/notification-settings-dialog";
import { BroadcastMessageDialog, BROADCAST_SENDER_EMAIL } from "@/components/push/broadcast-message-dialog";
import { BarcodeScannerDialog } from "@/components/shopping/barcode-scanner-dialog";
import { MemberAvatar } from "@/components/identity/member-avatar";
import { MembersDialog } from "@/components/identity/members-dialog";
import { AssistantDialog } from "@/components/assistant/assistant-dialog";
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
  const [profileOpen, setProfileOpen] = useState(false);
  const [membersOpen, setMembersOpen] = useState(false);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [notificationsOpen, setNotificationsOpen] = useState(false);
  const [broadcastOpen, setBroadcastOpen] = useState(false);
  const [scannerOpen, setScannerOpen] = useState(false);
  const assistantOpen = useAssistantOpen((s) => s.open);
  const setAssistantOpen = useAssistantOpen((s) => s.setOpen);

  const me = actingMemberId ? members[actingMemberId] : undefined;
  const canBroadcast = me?.email === BROADCAST_SENDER_EMAIL;

  return (
    <>
      <header className="glass surface-shadow sticky top-0 z-40 w-full rounded-b-3xl border-b border-border/40 pt-[env(safe-area-inset-top)] pl-[env(safe-area-inset-left)] pr-[env(safe-area-inset-right)]">
      {/* Rendered inside the header (not as a separate sticky sibling) so the
          "you're offline" state stays pinned on screen while scrolling,
          instead of disappearing after the first swipe — exactly when a
          stalled write is most likely to be on someone's mind. */}
      <OfflineBanner />
      <div className="mx-auto flex w-full max-w-3xl items-center gap-3 px-4 pt-2 pb-2">
      <Link href="/" className="flex items-center gap-2 text-lg font-bold">
        <span className="text-xl">💙</span>
        <span className="hidden text-foreground sm:inline">{t("appName")}</span>
      </Link>

      <div className="ms-auto flex items-center gap-1">
        <Button variant="ghost" size="icon" onClick={() => setSearchOpen(true)} aria-label={t("search")} title={t("search")}>
          <Search className="size-4" />
        </Button>
        <Button variant="ghost" size="icon" onClick={() => setAssistantOpen(true)} aria-label={t("assistantTitle")} title={t("assistantTitle")}>
          <Bot className="size-4" />
        </Button>
        <Button variant="ghost" size="icon" nativeButton={false} render={<Link href="/calendar" />} aria-label={t("calendar")} title={t("calendar")}>
          <CalendarDays className="size-4" />
        </Button>

        <DropdownMenu>
          <DropdownMenuTrigger render={<Button variant="ghost" size="icon" aria-label={t("more")} title={t("more")} />}>
            <MoreHorizontal className="size-4" />
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-48">
            <DropdownMenuItem onClick={() => setScannerOpen(true)}>
              <ScanBarcode className="size-4" /> {t("scanBarcode")}
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => setNotificationsOpen(true)}>
              <Bell className="size-4" /> {t("notifications")}
            </DropdownMenuItem>
            {canBroadcast && (
              <DropdownMenuItem onClick={() => setBroadcastOpen(true)}>
                <Megaphone className="size-4" /> {t("sendMessage")}
              </DropdownMenuItem>
            )}
          </DropdownMenuContent>
        </DropdownMenu>

        <DropdownMenu>
          <DropdownMenuTrigger render={<Button variant="ghost" className="h-auto gap-1.5 px-2 py-1" aria-label={me?.display_name ?? t("settings")} />}>
            {me ? (
              <>
                <MemberAvatar member={me} className="size-8" />
                <span className="hidden sm:inline">{me.display_name}</span>
              </>
            ) : (
              <Users className="size-4" />
            )}
            <ChevronDown className="size-3.5 opacity-60" />
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-56">
            <DropdownMenuGroup>
              {me && (
                <DropdownMenuItem onClick={() => setProfileOpen(true)}>
                  <Pencil className="size-4" /> {t("editProfile")}
                </DropdownMenuItem>
              )}
              <DropdownMenuItem onClick={() => setMembersOpen(true)}>
                <Users className="size-4" /> {t("householdMembers")}
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => setHistoryOpen(true)}>
                <History className="size-4" /> {t("history")}
              </DropdownMenuItem>
            </DropdownMenuGroup>
            <DropdownMenuSeparator />
            <DropdownMenuGroup>
              <DropdownMenuLabel>{t("language")}</DropdownMenuLabel>
              <DropdownMenuItem onClick={() => setLocale("he")} className="justify-between">
                עברית {locale === "he" && <Check className="size-3.5" />}
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => setLocale("en")} className="justify-between">
                English {locale === "en" && <Check className="size-3.5" />}
              </DropdownMenuItem>
            </DropdownMenuGroup>
            <DropdownMenuSeparator />
            <DropdownMenuGroup>
              <DropdownMenuLabel>{t("theme")}</DropdownMenuLabel>
              <DropdownMenuItem onClick={() => setTheme("light")} className="justify-between">
                <span className="flex items-center gap-2"><Sun className="size-4" /> {t("light")}</span> {theme === "light" && <Check className="size-3.5" />}
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => setTheme("dark")} className="justify-between">
                <span className="flex items-center gap-2"><Moon className="size-4" /> {t("dark")}</span> {theme === "dark" && <Check className="size-3.5" />}
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => setTheme("system")} className="justify-between">
                <span className="flex items-center gap-2"><Laptop className="size-4" /> {t("system")}</span> {theme === "system" && <Check className="size-3.5" />}
              </DropdownMenuItem>
            </DropdownMenuGroup>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
      </div>
      </header>

      <ProfileEditDialog memberId={actingMemberId} open={profileOpen} onOpenChange={setProfileOpen} />
      <MembersDialog open={membersOpen} onOpenChange={setMembersOpen} />
      <HistoryDialog open={historyOpen} onOpenChange={setHistoryOpen} />
      <NotificationSettingsDialog open={notificationsOpen} onOpenChange={setNotificationsOpen} />
      {canBroadcast && (
        <BroadcastMessageDialog open={broadcastOpen} onOpenChange={setBroadcastOpen} actorId={actingMemberId} />
      )}
      <BarcodeScannerDialog open={scannerOpen} onOpenChange={setScannerOpen} createdBy={actingMemberId} />
      <AssistantDialog open={assistantOpen} onOpenChange={setAssistantOpen} />
    </>
  );
}

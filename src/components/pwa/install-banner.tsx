"use client";

import { useState, useSyncExternalStore } from "react";
import { Share, SquarePlus, Plus, X } from "lucide-react";
import { useT } from "@/lib/i18n/store";
import { useInstallPrompt } from "@/lib/pwa/use-install-prompt";
import { useStandalone } from "@/lib/pwa/use-standalone";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";

const DISMISS_KEY = "kh-install-banner-dismissed";
const DISMISS_EVENT = "kh-install-banner-dismiss-changed";

function subscribeDismissed(callback: () => void) {
  window.addEventListener(DISMISS_EVENT, callback);
  return () => window.removeEventListener(DISMISS_EVENT, callback);
}
function getDismissedSnapshot() {
  return localStorage.getItem(DISMISS_KEY) === "1";
}
function getDismissedServerSnapshot() {
  return false;
}

function subscribeNever() {
  return () => {};
}
function getIsIOSSnapshot() {
  return /iphone|ipad|ipod/i.test(navigator.userAgent);
}
function getIsIOSServerSnapshot() {
  return false;
}

const STEPS = [
  { icon: Share, key: "installStep1" as const },
  { icon: SquarePlus, key: "installStep2" as const },
  { icon: Plus, key: "installStep3" as const },
];

export function InstallBanner() {
  const t = useT();
  const isStandalone = useStandalone();
  const { canInstall, promptInstall } = useInstallPrompt();
  const dismissed = useSyncExternalStore(subscribeDismissed, getDismissedSnapshot, getDismissedServerSnapshot);
  const isIOS = useSyncExternalStore(subscribeNever, getIsIOSSnapshot, getIsIOSServerSnapshot);
  const [stepsOpen, setStepsOpen] = useState(false);

  // Only show when there's an actual path to install: a native prompt
  // (Android/desktop Chrome) or a browser we know how to walk through by hand.
  // Gates only the banner row, not the dialog below — dismissing the banner
  // (which happens the moment "Install" is tapped) must not unmount the
  // steps dialog it just opened.
  const showBanner = !isStandalone && !dismissed && (canInstall || isIOS);

  function dismiss() {
    localStorage.setItem(DISMISS_KEY, "1");
    window.dispatchEvent(new Event(DISMISS_EVENT));
  }

  async function handleInstallClick() {
    if (canInstall) {
      await promptInstall();
    } else {
      setStepsOpen(true);
    }
    dismiss();
  }

  return (
    <>
      {showBanner && (
        <div className="glass flex items-center gap-3 border-b px-4 py-2.5">
          <span className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-primary/15 text-xl">
            💙
          </span>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-medium">{t("installBannerTitle")}</p>
            <p className="truncate text-xs text-muted-foreground">{t("installBannerSubtitle")}</p>
          </div>
          <Button size="sm" className="shrink-0 rounded-full" onClick={handleInstallClick}>
            {t("installApp")}
          </Button>
          <Button variant="ghost" size="icon-sm" className="shrink-0" onClick={dismiss} aria-label={t("close")}>
            <X className="size-4" />
          </Button>
        </div>
      )}

      <Dialog open={stepsOpen} onOpenChange={setStepsOpen}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>{t("installStepsTitle")}</DialogTitle>
          </DialogHeader>
          <ol className="flex flex-col gap-4 py-1">
            {STEPS.map(({ icon: Icon, key }, i) => (
              <li key={key} className="flex items-center gap-3">
                <span className="flex size-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-sm font-semibold text-primary">
                  {i + 1}
                </span>
                <Icon className="size-5 shrink-0 text-muted-foreground" />
                <span className="text-sm">{t(key)}</span>
              </li>
            ))}
          </ol>
        </DialogContent>
      </Dialog>
    </>
  );
}

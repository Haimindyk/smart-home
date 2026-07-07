"use client";

import { useSyncExternalStore } from "react";
import { WifiOff } from "lucide-react";
import { useT } from "@/lib/i18n/store";

function subscribe(callback: () => void) {
  window.addEventListener("online", callback);
  window.addEventListener("offline", callback);
  return () => {
    window.removeEventListener("online", callback);
    window.removeEventListener("offline", callback);
  };
}

export function OfflineBanner() {
  const isOnline = useSyncExternalStore(
    subscribe,
    () => navigator.onLine,
    () => true
  );
  const t = useT();

  if (isOnline) return null;

  return (
    <div className="flex items-center justify-center gap-2 bg-amber-500/90 py-1.5 text-xs font-medium text-amber-950">
      <WifiOff className="size-3.5" />
      {t("offline")}
    </div>
  );
}

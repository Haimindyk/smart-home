"use client";

import { useSyncExternalStore } from "react";

type NavigatorStandalone = Navigator & { standalone?: boolean };

function isStandalone() {
  if (typeof window === "undefined") return true;
  return window.matchMedia("(display-mode: standalone)").matches || (navigator as NavigatorStandalone).standalone === true;
}

function subscribe(callback: () => void) {
  const mql = window.matchMedia("(display-mode: standalone)");
  mql.addEventListener("change", callback);
  return () => mql.removeEventListener("change", callback);
}

/** Whether the app is currently running as an installed PWA (not a browser tab). */
export function useStandalone() {
  return useSyncExternalStore(subscribe, isStandalone, () => true);
}

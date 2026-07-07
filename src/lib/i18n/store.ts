"use client";

import { create } from "zustand";
import { persist } from "zustand/middleware";
import { messages, type Locale, type MessageKey } from "./messages";

type LocaleState = {
  locale: Locale;
  setLocale: (locale: Locale) => void;
};

export const useLocaleStore = create<LocaleState>()(
  persist(
    (set) => ({
      locale: "he",
      setLocale: (locale) => set({ locale }),
    }),
    { name: "kh-locale" }
  )
);

export function useT() {
  const locale = useLocaleStore((s) => s.locale);
  return (key: MessageKey) => messages[locale][key];
}

export function dirFor(locale: Locale) {
  return locale === "he" ? "rtl" : "ltr";
}

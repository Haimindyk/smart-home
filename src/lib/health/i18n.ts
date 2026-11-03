"use client";
import { useLocaleStore } from "@/lib/i18n/store";
export function useHealthText() {
  const locale = useLocaleStore((s) => s.locale);
  return (he: string, en: string) => (locale === "he" ? he : en);
}

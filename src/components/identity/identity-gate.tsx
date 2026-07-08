"use client";

import { useState } from "react";
import { Delete } from "lucide-react";
import { useIdentity } from "@/lib/identity";
import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import { Card } from "@/components/ui/card";
import { cn } from "@/lib/utils";

const PIN_LENGTH = 4;
const KEYS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "back"] as const;

export function IdentityGate({ children }: { children: React.ReactNode }) {
  const actingMemberId = useIdentity((s) => s.actingMemberId);
  const setActingMemberId = useIdentity((s) => s.setActingMemberId);
  const members = useAppStore((s) => s.members);
  const hydrated = useAppStore((s) => s.hydrated);
  const t = useT();
  const [pin, setPin] = useState("");
  const [shake, setShake] = useState(false);

  const memberList = Object.values(members);

  function press(key: string) {
    if (key === "back") {
      setPin((p) => p.slice(0, -1));
      return;
    }
    if (!key || pin.length >= PIN_LENGTH) return;

    const next = pin + key;
    setPin(next);
    if (next.length < PIN_LENGTH) return;

    const match = memberList.find((m) => m.pin && m.pin === next);
    if (match) {
      setActingMemberId(match.id);
    } else {
      setShake(true);
      setTimeout(() => {
        setShake(false);
        setPin("");
      }, 500);
    }
  }

  // Don't block on a slow network — once we know who's here, or once data has
  // hydrated with nobody chosen yet, decide; otherwise just render the app.
  if (actingMemberId || (!hydrated && memberList.length === 0)) {
    return <>{children}</>;
  }

  if (hydrated && memberList.length === 0) {
    return <>{children}</>;
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center overflow-hidden bg-background p-6">
      <div className="pointer-events-none absolute -top-24 start-1/2 size-96 -translate-x-1/2 rounded-full bg-primary/20 blur-3xl" />
      <Card className="glass surface-shadow relative w-full max-w-xs gap-5 rounded-3xl p-7 text-center ring-1 ring-border/40">
        <div>
          <div className="mb-3 text-5xl">💙</div>
          <h1 className="text-2xl font-bold tracking-tight">{t("whoAreYou")}</h1>
          <p className="mt-1.5 text-sm text-muted-foreground">{t("enterYourCode")}</p>
        </div>

        <div className={cn("flex justify-center gap-3", shake && "animate-shake")}>
          {Array.from({ length: PIN_LENGTH }).map((_, i) => (
            <span
              key={i}
              className={cn(
                "size-3.5 rounded-full border-2 border-primary/40 transition-all",
                i < pin.length && "scale-110 border-primary bg-primary"
              )}
            />
          ))}
        </div>

        <div className="grid grid-cols-3 gap-2">
          {KEYS.map((key, i) =>
            key === "" ? (
              <span key={i} />
            ) : (
              <button
                key={i}
                type="button"
                onClick={() => press(key)}
                className="flex h-12 items-center justify-center rounded-2xl bg-accent/50 text-lg font-medium transition-[background-color,transform] duration-150 ease-(--ease-premium) hover:bg-accent active:scale-90"
              >
                {key === "back" ? <Delete className="size-5" /> : key}
              </button>
            )
          )}
        </div>
      </Card>
    </div>
  );
}

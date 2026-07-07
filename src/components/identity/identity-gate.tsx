"use client";

import { useEffect, useState } from "react";
import { Delete } from "lucide-react";
import { useIdentity } from "@/lib/identity";
import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import { Button } from "@/components/ui/button";
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
  const [pickedGuest, setPickedGuest] = useState(false);
  const [pin, setPin] = useState("");
  const [shake, setShake] = useState(false);

  const memberList = Object.values(members);

  useEffect(() => {
    if (pin.length < PIN_LENGTH) return;
    const match = memberList.find((m) => m.pin && m.pin === pin);
    if (match) {
      setActingMemberId(match.id);
    } else {
      setShake(true);
      const timeout = setTimeout(() => {
        setShake(false);
        setPin("");
      }, 500);
      return () => clearTimeout(timeout);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pin]);

  function press(key: string) {
    if (key === "back") {
      setPin((p) => p.slice(0, -1));
    } else if (key && pin.length < PIN_LENGTH) {
      setPin((p) => p + key);
    }
  }

  // Don't block on a slow network — once we know who's here, or once data has
  // hydrated with nobody chosen yet, decide; otherwise just render the app.
  if (actingMemberId || pickedGuest || (!hydrated && memberList.length === 0)) {
    return <>{children}</>;
  }

  if (hydrated && memberList.length === 0) {
    return <>{children}</>;
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center overflow-hidden bg-background p-6">
      <div className="pointer-events-none absolute -top-24 start-1/2 size-96 -translate-x-1/2 rounded-full bg-gradient-to-br from-indigo-400/25 to-violet-500/20 blur-3xl" />
      <Card className="glass relative w-full max-w-xs gap-5 rounded-3xl p-7 text-center shadow-2xl ring-1 ring-border/60">
        <div>
          <div className="mb-3 text-5xl">💙</div>
          <h1 className="text-xl font-semibold tracking-tight">{t("whoAreYou")}</h1>
          <p className="mt-1.5 text-sm text-muted-foreground">{t("enterYourCode")}</p>
        </div>

        <div className={cn("flex justify-center gap-3", shake && "animate-shake")}>
          {Array.from({ length: PIN_LENGTH }).map((_, i) => (
            <span
              key={i}
              className={cn(
                "size-3.5 rounded-full border-2 border-primary/40 transition-all",
                i < pin.length && "scale-110 border-primary bg-gradient-to-br from-indigo-500 to-violet-600"
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
                className="flex h-12 items-center justify-center rounded-2xl bg-accent/50 text-lg font-medium transition-colors hover:bg-accent active:scale-95"
              >
                {key === "back" ? <Delete className="size-5" /> : key}
              </button>
            )
          )}
        </div>

        <Button variant="ghost" size="lg" className="rounded-2xl" onClick={() => setPickedGuest(true)}>
          {t("guest")}
        </Button>
      </Card>
    </div>
  );
}

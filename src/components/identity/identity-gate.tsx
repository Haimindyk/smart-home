"use client";

import { useState } from "react";
import { useIdentity } from "@/lib/identity";
import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";

export function IdentityGate({ children }: { children: React.ReactNode }) {
  const actingMemberId = useIdentity((s) => s.actingMemberId);
  const setActingMemberId = useIdentity((s) => s.setActingMemberId);
  const members = useAppStore((s) => s.members);
  const hydrated = useAppStore((s) => s.hydrated);
  const t = useT();
  const [pickedGuest, setPickedGuest] = useState(false);

  const memberList = Object.values(members);

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
      <Card className="glass relative w-full max-w-sm gap-6 rounded-3xl p-7 text-center shadow-2xl ring-1 ring-border/60">
        <div>
          <div className="mb-3 text-5xl">💙</div>
          <h1 className="text-xl font-semibold tracking-tight">{t("whoAreYou")}</h1>
          <p className="mt-1.5 text-sm text-muted-foreground">{t("whoAreYouSubtitle")}</p>
        </div>
        <div className="flex flex-col gap-2">
          {memberList.map((member) => (
            <button
              key={member.id}
              onClick={() => setActingMemberId(member.id)}
              className="flex items-center gap-3 rounded-2xl border border-transparent bg-accent/40 px-4 py-3 text-start text-base font-medium transition-all hover:-translate-y-0.5 hover:shadow-md"
              style={{ boxShadow: `inset 0 0 0 1.5px ${member.color}40` }}
            >
              <span
                className="flex size-9 shrink-0 items-center justify-center rounded-full text-lg"
                style={{ backgroundColor: `${member.color}22` }}
              >
                {member.avatar_emoji}
              </span>
              <span dir="auto">{member.display_name}</span>
            </button>
          ))}
          <Button variant="ghost" size="lg" className="rounded-2xl" onClick={() => setPickedGuest(true)}>
            {t("guest")}
          </Button>
        </div>
      </Card>
    </div>
  );
}

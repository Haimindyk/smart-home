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
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-gradient-to-br from-background via-background to-muted p-6">
      <Card className="w-full max-w-sm gap-6 p-6 text-center shadow-xl">
        <div>
          <div className="mb-2 text-4xl">💙</div>
          <h1 className="text-xl font-semibold">{t("whoAreYou")}</h1>
          <p className="mt-1 text-sm text-muted-foreground">{t("whoAreYouSubtitle")}</p>
        </div>
        <div className="flex flex-col gap-2">
          {memberList.map((member) => (
            <Button
              key={member.id}
              variant="outline"
              size="lg"
              className="justify-start gap-3 text-base"
              style={{ borderColor: member.color }}
              onClick={() => setActingMemberId(member.id)}
            >
              <span className="text-xl">{member.avatar_emoji}</span>
              {member.display_name}
            </Button>
          ))}
          <Button variant="ghost" size="lg" onClick={() => setPickedGuest(true)}>
            {t("guest")}
          </Button>
        </div>
      </Card>
    </div>
  );
}

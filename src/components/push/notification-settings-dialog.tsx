"use client";

import { useEffect, useState } from "react";
import { Bell, BellOff } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { useIdentity } from "@/lib/identity";
import { useT } from "@/lib/i18n/store";
import { usePush } from "@/lib/push/use-push";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import type { MessageKey } from "@/lib/i18n/messages";

type PrefsState = {
  on_create: boolean;
  on_complete: boolean;
  on_assigned_me: boolean;
  on_shopping: boolean;
  muted: boolean;
};

const DEFAULT_PREFS: PrefsState = {
  on_create: true,
  on_complete: true,
  on_assigned_me: true,
  on_shopping: true,
  muted: false,
};

const CATEGORY_ROWS: { key: keyof Omit<PrefsState, "muted">; label: MessageKey }[] = [
  { key: "on_create", label: "notifyOnCreate" },
  { key: "on_complete", label: "notifyOnComplete" },
  { key: "on_assigned_me", label: "notifyOnAssignedMe" },
  { key: "on_shopping", label: "notifyOnShopping" },
];

export function NotificationSettingsDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const t = useT();
  const memberId = useIdentity((s) => s.actingMemberId);
  const { supported, permission, subscribed, loading, subscribe, unsubscribe } = usePush();
  const [prefs, setPrefs] = useState<PrefsState>(DEFAULT_PREFS);

  useEffect(() => {
    if (!open || !memberId) return;
    let cancelled = false;
    const supabase = createClient();
    supabase
      .from("notification_prefs")
      .select("on_create, on_complete, on_assigned_me, on_shopping, muted")
      .eq("member_id", memberId)
      .maybeSingle()
      .then(({ data }) => {
        if (cancelled) return;
        setPrefs(data ? { ...DEFAULT_PREFS, ...data } : DEFAULT_PREFS);
      });
    return () => {
      cancelled = true;
    };
  }, [open, memberId]);

  async function updatePrefs(patch: Partial<PrefsState>) {
    if (!memberId) return;
    const next = { ...prefs, ...patch };
    setPrefs(next);
    const supabase = createClient();
    await supabase
      .from("notification_prefs")
      .upsert({ member_id: memberId, ...next, updated_at: new Date().toISOString() }, { onConflict: "member_id" });
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Bell className="size-4" /> {t("notifications")}
          </DialogTitle>
        </DialogHeader>

        {!supported ? (
          <p className="py-4 text-sm text-muted-foreground">{t("notificationsUnsupported")}</p>
        ) : (
          <div className="flex flex-col gap-4 py-2">
            <div className="flex items-center justify-between gap-3 rounded-lg border p-3">
              <div className="flex items-center gap-2.5">
                {subscribed ? <Bell className="size-4 text-primary" /> : <BellOff className="size-4 text-muted-foreground" />}
                <div className="flex flex-col">
                  <Label>{t("enableNotifications")}</Label>
                  {permission === "denied" && (
                    <span className="text-xs text-muted-foreground">{t("notificationsBlocked")}</span>
                  )}
                </div>
              </div>
              <Switch
                checked={subscribed}
                disabled={loading || permission === "denied"}
                onCheckedChange={(checked) => {
                  if (checked) void subscribe();
                  else void unsubscribe();
                }}
              />
            </div>

            {subscribed && (
              <div className="flex flex-col gap-3">
                {CATEGORY_ROWS.map(({ key, label }) => (
                  <div key={key} className="flex items-center justify-between gap-3">
                    <Label className="font-normal">{t(label)}</Label>
                    <Switch
                      checked={prefs[key] && !prefs.muted}
                      disabled={prefs.muted}
                      onCheckedChange={(checked) => void updatePrefs({ [key]: checked } as Partial<PrefsState>)}
                    />
                  </div>
                ))}

                <div className="flex items-center justify-between gap-3 border-t pt-3">
                  <Label className="font-normal">{t("muteAllNotifications")}</Label>
                  <Switch checked={prefs.muted} onCheckedChange={(checked) => void updatePrefs({ muted: checked })} />
                </div>
              </div>
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

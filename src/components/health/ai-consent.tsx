"use client";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { useHealthStore } from "@/lib/health/store";
import { wellnessRequest } from "@/lib/health/wellness-api";
import { adult } from "../../../supabase/functions/_shared/wellness-core";
import { localDate } from "@/lib/health/calculations";
import { useHealthText } from "@/lib/health/i18n";
import { ErrorText } from "./shared";
const capabilities = new Map<
  string,
  {
    until: number;
    promise: Promise<{ available: boolean; serviceReady: boolean }>;
  }
>();
function capability(owner: string) {
  const cached = capabilities.get(owner);
  if (cached && cached.until > Date.now()) return cached.promise;
  const promise = wellnessRequest<{
    available: boolean;
    serviceReady: boolean;
  }>({ action: "capabilities" });
  capabilities.set(owner, { until: Date.now() + 30000, promise });
  promise.catch(() => capabilities.delete(owner));
  return promise;
}
export function useWellnessAvailability() {
  const owner = useHealthStore((s) => s.owner),
    profile = useHealthStore((s) => s.data.health_profiles[0]?.data),
    pending = useHealthStore((s) => s.pending);
  const [state, setState] = useState<{
    owner: string | null;
    available: boolean;
    serviceReady: boolean;
    checked: boolean;
  }>({ owner: null, available: false, serviceReady: false, checked: false });
  useEffect(() => {
    let cancelled = false;
    if (owner)
      void capability(owner)
        .then((r) => {
          if (!cancelled)
            setState({
              owner,
              available: r.available,
              serviceReady: r.serviceReady,
              checked: true,
            });
        })
        .catch(() => {
          if (!cancelled)
            setState({
              owner,
              available: false,
              serviceReady: false,
              checked: true,
            });
        });
    return () => {
      cancelled = true;
    };
  }, [owner]);
  const eligible = !!profile && adult(profile, localDate(profile.timezone));
  return {
    manageReady: state.owner === owner && state.serviceReady && pending === 0,
    available: state.owner === owner && state.available,
    checked: state.owner === owner && state.checked,
    eligible,
    consented: !!profile?.aiProviderConsent,
    ready:
      state.owner === owner &&
      state.available &&
      eligible &&
      !!profile?.aiProviderConsent &&
      pending === 0,
  };
}
export function AiConsent() {
  const h = useHealthText(),
    profile = useHealthStore((s) => s.data.health_profiles[0]),
    save = useHealthStore((s) => s.save),
    state = useWellnessAvailability();
  const [error, setError] = useState<string | null>(null),
    [busy, setBusy] = useState(false);
  if (!state.checked)
    return (
      <p role="status" className="text-sm text-muted-foreground">
        {h("בודק זמינות המאמן…", "Checking AI availability…")}
      </p>
    );
  if (!state.available)
    return (
      <p className="rounded-xl bg-muted p-3 text-sm">
        {h(
          "השירות האישי עדיין לא הופעל. אפשר להמשיך לתעד ולערוך ידנית.",
          "The personal AI service is not enabled yet. You can keep logging and editing manually.",
        )}
      </p>
    );
  if (!state.eligible)
    return (
      <p className="text-sm text-muted-foreground">
        {h(
          "המלצות AI מיועדות לבני 18 ומעלה. יש להשלים תאריך לידה בהגדרות.",
          "AI recommendations are for adults 18+. Complete your birth date in Settings.",
        )}
      </p>
    );
  if (state.consented) return null;
  return (
    <div className="rounded-xl border bg-muted/30 p-4 text-sm">
      <p>
        {h(
          "כדי לקבל הערכות והצעות, תוכן הבקשה הדרוש יישלח לעיבוד ב־Cloudflare. לא נשלחים שם, PIN או פרופיל גוף מלא. אין שימוש בתוכן לאימון המודלים. הערכות דורשות בדיקה, וכל שינוי בתוכנית מחייב אישור שלך.",
          "Relevant request content is processed by Cloudflare. Your name, PIN and full body profile are not sent. Content is not used to train models. Estimates need review; every plan change requires your approval.",
        )}
      </p>
      <ErrorText error={error} />
      <Button
        className="mt-3"
        disabled={busy || !profile}
        onClick={async () => {
          if (!profile) return;
          setBusy(true);
          setError(null);
          try {
            await save(
              "health_profiles",
              { ...profile.data, aiProviderConsent: true },
              profile,
            );
          } catch (e) {
            setError(e instanceof Error ? e.message : "failed");
          } finally {
            setBusy(false);
          }
        }}
      >
        {h("מאשר/ת שימוש ב־AI האישי", "Enable personal AI")}
      </Button>
    </div>
  );
}

"use client";
import Image from "next/image";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/client";
import { useHealthStore } from "@/lib/health/store";
import { wellnessRequest } from "@/lib/health/wellness-api";
import { resolveCatalogExercise } from "../../../supabase/functions/_shared/exercise-catalog";
import type { Exercise } from "@/lib/health/model";
import { useHealthText } from "@/lib/health/i18n";
import { useWellnessAvailability } from "./ai-consent";
import { ErrorText } from "./shared";
type Illustration = {
  image_path: string;
  status: "pending_review" | "reviewed";
};
// Serialize creation for this browser. Server reservations also serialize across devices.
let queue: Promise<unknown> = Promise.resolve();
const cache = new Map<string, Promise<Illustration>>();
function illustration(owner: string, catalogId: string) {
  const key = owner + ":" + catalogId;
  let result = cache.get(key);
  if (!result) {
    result = queue
      .catch(() => {})
      .then(async () => {
        const state = useHealthStore.getState();
        if (
          state.owner !== owner ||
          !state.data.health_profiles[0]?.data.aiProviderConsent
        )
          throw new Error("session_mismatch");
        return wellnessRequest<Illustration>({
          action: "illustration",
          catalogId,
          requestId: crypto.randomUUID(),
        });
      });
    queue = result;
    cache.set(key, result);
    result.catch(() => cache.delete(key));
  }
  return result;
}
export function ExerciseIllustration({
  exercise,
  thumbnail = false,
}: {
  exercise: Exercise;
  thumbnail?: boolean;
}) {
  const h = useHealthText(),
    owner = useHealthStore((s) => s.owner),
    availability = useWellnessAvailability();
  const catalog = resolveCatalogExercise(exercise.name, exercise.catalogId),
    key = owner + ":" + catalog?.id;
  const [state, setState] = useState<{
    key: string;
    url: string;
    status: string;
    error: string | null;
  }>({ key: "", url: "", status: "", error: null });
  useEffect(() => {
    let cancelled = false;
    if (!owner || !catalog || !availability.ready) return;
    void illustration(owner, catalog.id)
      .then(async (result) => {
        const response = await createClient()
          .storage.from("health-images")
          .createSignedUrl(result.image_path, 300);
        if (response.error) throw new Error("failed");
        if (!cancelled && useHealthStore.getState().owner === owner)
          setState({
            key,
            url: response.data.signedUrl,
            status: result.status,
            error: null,
          });
      })
      .catch((e) => {
        if (!cancelled)
          setState({
            key,
            url: "",
            status: "",
            error: e instanceof Error ? e.message : "failed",
          });
      });
    return () => {
      cancelled = true;
    };
  }, [owner, catalog, key, availability.ready]);
  const current = state.key === key ? state : null;
  if (thumbnail)
    return current?.url ? (
      <Image
        unoptimized
        src={current.url}
        width={80}
        height={80}
        alt={h(
          "המחשת AI לתרגיל — לבדיקה",
          "AI exercise illustration — review needed",
        )}
        className="exercise-thumb"
      />
    ) : (
      <span
        className="exercise-thumb flex items-center justify-center bg-muted"
        aria-hidden="true"
      >
        ↗
      </span>
    );
  if (!catalog)
    return (
      <p className="text-sm text-muted-foreground">
        {h(
          "יש לבחור את סוג התרגיל והציוד המדויקים כדי להתאים המחשה. השמירה זמינה גם ללא תמונה.",
          "Choose the exact exercise and equipment to attach an illustration. You can save without an image.",
        )}
      </p>
    );
  return (
    <div className="grid gap-3 rounded-xl border p-3">
      <p className="text-xs text-muted-foreground">
        {h(
          "המחשת AI: עמדה התחלתית משמאל וסופית מימין. ייתכנו טעויות בטכניקה; יש לבדוק מול מקור מקצועי לפני הסתמכות.",
          "AI illustration: start on the left, finish on the right. Technique may be incorrect; check against a qualified source before relying on it.",
        )}
      </p>
      {current?.url ? (
        <Image
          unoptimized
          src={current.url}
          width={640}
          height={400}
          className="max-h-72 w-full rounded-xl object-contain"
          alt={`${exercise.name} — ${h("המחשת התחלה וסיום שנוצרה ב־AI", "AI-generated start and finish illustration")}`}
        />
      ) : (
        <p role="status" className="text-sm">
          {availability.ready && !current?.error
            ? h("ההמחשה נוצרת ברקע…", "Illustration is being prepared…")
            : h(
                "התרגיל נשמר גם כשהמחשה אינה זמינה.",
                "The exercise can be saved even without an illustration.",
              )}
        </p>
      )}
      <ErrorText error={current?.error ?? null} />
      {current?.status === "pending_review" && (
        <Button
          variant="outline"
          onClick={async () => {
            try {
              await wellnessRequest({
                action: "review",
                catalogId: catalog.id,
              });
              setState((s) => ({ ...s, status: "reviewed" }));
            } catch (e) {
              setState((s) => ({
                ...s,
                error: e instanceof Error ? e.message : "failed",
              }));
            }
          }}
        >
          {h(
            "בדקתי את ההמחשה מול מקור אמין",
            "I checked this against a reliable source",
          )}
        </Button>
      )}
      {current?.status === "reviewed" && (
        <p className="text-xs text-muted-foreground">
          {h("נבדקה על ידך · נוצרה ב־AI", "Reviewed by you · AI-generated")}
        </p>
      )}
    </div>
  );
}

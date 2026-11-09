"use client";
import { useEffect, useRef, useState } from "react";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { useHealthStore } from "@/lib/health/store";
import { uploadMealImage } from "@/lib/health/api";
import { estimateMeal } from "@/lib/health/wellness-api";
import { useHealthText } from "@/lib/health/i18n";
import { AiConsent, useWellnessAvailability } from "./ai-consent";
export function MealCamera({
  date,
  onClose,
}: {
  date: string;
  onClose: () => void;
}) {
  const h = useHealthText(),
    availability = useWellnessAvailability(),
    video = useRef<HTMLVideoElement>(null),
    gallery = useRef<HTMLInputElement>(null),
    lock = useRef(false);
  const attempt = useRef<{
    id: string;
    file: File;
    path?: string;
    result?: Awaited<ReturnType<typeof estimateMeal>>;
  } | null>(null);
  const [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [noCamera, setNoCamera] = useState(false);
  useEffect(() => {
    let disposed = false;
    let stream: MediaStream | undefined;
    if (!navigator.mediaDevices) {
      queueMicrotask(() => {
        if (!disposed) setNoCamera(true);
      });
      return () => {
        disposed = true;
      };
    }
    void navigator.mediaDevices
      .getUserMedia({
        video: { facingMode: { ideal: "environment" } },
        audio: false,
      })
      .then((s) => {
        stream = s;
        if (disposed) s.getTracks().forEach((t) => t.stop());
        else if (video.current) video.current.srcObject = s;
      })
      .catch(() => setNoCamera(true));
    return () => {
      disposed = true;
      stream?.getTracks().forEach((t) => t.stop());
    };
  }, []);
  async function submit(file?: File) {
    if (lock.current || !availability.ready) return;
    if (file) attempt.current = { id: crypto.randomUUID(), file };
    const job = attempt.current;
    if (!job) return;
    lock.current = true;
    setBusy(true);
    setError("");
    const owner = useHealthStore.getState().owner;
    try {
      job.path ??= await uploadMealImage(job.file, owner!);
      job.result ??= await estimateMeal({
        requestId: job.id,
        mode: "meal",
        description: "",
        imagePath: job.path,
        automatic: true,
      });
      if (useHealthStore.getState().owner !== owner)
        throw Error("session_mismatch");
      if (!job.result.items.length) throw Error("no_food");
      if (!useHealthStore.getState().data.meals.some((m) => m.id === job.id))
        await useHealthStore
          .getState()
          .save(
            "meals",
            {
              date,
              kind: "snack",
              name: h("ארוחה מצולמת", "Photo meal"),
              items: job.result.items,
              imagePath: job.path,
              aiEstimate: { analysisId: job.id },
            },
            undefined,
            job.id,
          );
      onClose();
    } catch {
      setError(
        h(
          "לא הצלחנו להוסיף את הארוחה. אפשר לנסות שוב או לבחור תמונה אחרת.",
          "Could not add the meal. Retry or choose another photo.",
        ),
      );
    } finally {
      lock.current = false;
      setBusy(false);
    }
  }
  function capture() {
    const v = video.current;
    if (!v?.videoWidth || lock.current) return;
    const c = document.createElement("canvas"),
      scale = Math.min(1, 1536 / v.videoWidth);
    c.width = v.videoWidth * scale;
    c.height = v.videoHeight * scale;
    c.getContext("2d")?.drawImage(v, 0, 0, c.width, c.height);
    c.toBlob(
      (b) => {
        if (b) void submit(new File([b], "meal.jpg", { type: "image/jpeg" }));
      },
      "image/jpeg",
      0.85,
    );
  }
  return (
    <Dialog
      open
      onOpenChange={(o) => {
        if (!o && !lock.current) onClose();
      }}
    >
      <DialogContent className="health-meal-camera" showCloseButton={false}>
        <video
          ref={video}
          autoPlay
          playsInline
          muted
          aria-label={h("תצוגת מצלמה", "Camera preview")}
        />
        <header>
          <button
            disabled={busy}
            onClick={onClose}
            aria-label={h("סגירה", "Close")}
          >
            ×
          </button>
          <DialogTitle>{h("צילום ארוחה", "Photograph meal")}</DialogTitle>
        </header>
        <div className="health-camera-frame" aria-hidden="true" />
        <footer>
          {noCamera && (
            <p>
              {h(
                "המצלמה אינה זמינה. אפשר לבחור תמונה.",
                "Camera unavailable. Choose a photo.",
              )}
            </p>
          )}
          {!availability.ready && <AiConsent />}
          <p>
            {h(
              "הארוחה תתווסף כהערכה. אפשר לתקן ביומן.",
              "Added as an estimate. Correct it in your diary.",
            )}
          </p>
          <p>
            {h(
              "התמונה תישמר ביומן האישי עם הארוחה.",
              "The photo is saved with the meal in your private diary.",
            )}
          </p>
          {error && (
            <div role="alert">
              {error}
              <button disabled={busy} onClick={() => void submit()}>
                {h("ניסיון נוסף", "Retry")}
              </button>
            </div>
          )}
          <div className="health-camera-actions">
            <button
              disabled={busy || !availability.ready}
              onClick={() => gallery.current?.click()}
            >
              {h("גלריה", "Gallery")}
            </button>
            <button
              className="health-camera-shutter"
              disabled={busy || noCamera || !availability.ready}
              onClick={capture}
              aria-label={h("צילום", "Take photo")}
            />
            <span />
          </div>
          <p role="status">
            {busy
              ? h("מזהה ומוסיף ליומן…", "Analyzing and adding to diary…")
              : ""}
          </p>
          <input
            ref={gallery}
            hidden
            type="file"
            accept="image/*"
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) void submit(f);
              e.target.value = "";
            }}
          />
        </footer>
      </DialogContent>
    </Dialog>
  );
}

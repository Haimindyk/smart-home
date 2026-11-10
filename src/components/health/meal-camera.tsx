"use client";
import Image from "next/image";
import { Check, LoaderCircle } from "lucide-react";
import { mealTitle } from "@/lib/health/meal-presentation";
import { useEffect, useRef, useState } from "react";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { useHealthStore } from "@/lib/health/store";
import { uploadMealImage } from "@/lib/health/api";
import { estimateMeal } from "@/lib/health/wellness-api";
import { useHealthText } from "@/lib/health/i18n";
import { ErrorText } from "./shared";
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
    lock = useRef(false),
    capturing = useRef(false),
    finished = useRef(false);
  const attempt = useRef<{
    id: string;
    file: File;
    path?: string;
    result?: Awaited<ReturnType<typeof estimateMeal>>;
  } | null>(null);
  const [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [noCamera, setNoCamera] = useState(false),
    [noFood, setNoFood] = useState(false),
    [cameraReady, setCameraReady] = useState(false),
    [preview, setPreview] = useState<string | null>(null),
    [phase, setPhase] = useState<"upload" | "analysis" | "save">("upload");
  useEffect(
    () => () => {
      if (preview) URL.revokeObjectURL(preview);
    },
    [preview],
  );
  useEffect(() => {
    if (preview) return;
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
        if (!disposed) setNoCamera(false);
        if (disposed) s.getTracks().forEach((t) => t.stop());
        else if (video.current) video.current.srcObject = s;
      })
      .catch(() => {
        if (!disposed) setNoCamera(true);
      });
    return () => {
      disposed = true;
      stream?.getTracks().forEach((t) => t.stop());
    };
  }, [preview]);
  async function submit(file?: File) {
    if (lock.current || finished.current || !availability.ready) return;
    if (file) {
      attempt.current = { id: crypto.randomUUID(), file };
      setPreview(URL.createObjectURL(file));
    }
    const job = attempt.current;
    if (!job) return;
    lock.current = true;
    setBusy(true);
    setError("");
    setNoFood(false);
    const owner = useHealthStore.getState().owner;
    let stage = "upload";
    try {
      if (!job.path) {
        setPhase("upload");
        job.path = await uploadMealImage(job.file, owner!);
      }
      stage = "analysis";
      if (!job.result) setPhase("analysis");
      job.result ??= await estimateMeal({
        requestId: job.id,
        mode: "meal",
        description: "",
        imagePath: job.path,
        automatic: true,
      });
      if (useHealthStore.getState().owner !== owner)
        throw Error("session_mismatch");
      if (!job.result.items.length) {
        setNoFood(true);
        throw Error("no_food");
      }
      stage = "save";
      setPhase("save");
      if (!useHealthStore.getState().data.meals.some((m) => m.id === job.id))
        await useHealthStore.getState().save(
          "meals",
          {
            date,
            kind: "snack",
            name: mealTitle(job.result.items),
            items: job.result.items,
            imagePath: job.path,
            aiEstimate: { analysisId: job.id },
          },
          undefined,
          job.id,
        );
      else await useHealthStore.getState().flush();
      if (useHealthStore.getState().conflict?.row.id === job.id)
        throw new Error("sync_required");
      finished.current = true;
      onClose();
    } catch (e) {
      const code = e instanceof Error ? e.message : "failed";
      setError(
        [
          "not_configured",
          "rate_limited",
          "quota_exhausted",
          "session_required",
          "session_mismatch",
          "online_required",
          "invalid_image",
          "invalid_output",
          "provider_failed",
          "analysis_busy",
          "sync_required",
        ].includes(code)
          ? code
          : stage === "upload"
            ? "upload_failed"
            : stage === "save"
              ? "meal_save_failed"
              : "request_failed",
      );
    } finally {
      lock.current = false;
      setBusy(false);
    }
  }
  function capture() {
    const v = video.current;
    if (!v?.videoWidth || lock.current || capturing.current || finished.current)
      return;
    capturing.current = true;
    const c = document.createElement("canvas"),
      scale = Math.min(1, 1536 / v.videoWidth);
    c.width = v.videoWidth * scale;
    c.height = v.videoHeight * scale;
    c.getContext("2d")?.drawImage(v, 0, 0, c.width, c.height);
    c.toBlob(
      (b) => {
        if (b)
          void submit(
            new File([b], "meal.jpg", { type: "image/jpeg" }),
          ).finally(() => {
            capturing.current = false;
          });
        else {
          capturing.current = false;
          setError(
            h("הצילום נכשל. נסו שוב.", "Capture failed. Please try again."),
          );
        }
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
      <DialogContent
        className="health-meal-camera"
        style={{
          translate: "0 0",
          maxHeight: "none",
          fontFamily: "var(--font-heebo),Arial,sans-serif",
        }}
        blurOverlay={false}
        showCloseButton={false}
      >
        <video
          style={{ zIndex: 0, display: preview ? "none" : undefined }}
          ref={video}
          autoPlay
          playsInline
          muted
          onLoadedData={() => setCameraReady(true)}
          aria-label={h("תצוגת מצלמה", "Camera preview")}
        />
        {preview && (
          <Image
            src={preview}
            alt={h("הארוחה שצולמה", "Captured meal")}
            fill
            sizes="100vw"
            unoptimized
            className="health-capture-preview"
          />
        )}
        {preview && busy && (
          <div className="health-capture-scan" aria-hidden="true">
            <span />
          </div>
        )}
        <header style={{ zIndex: 1 }}>
          <button
            disabled={busy}
            onClick={onClose}
            aria-label={h("סגירה", "Close")}
          >
            ×
          </button>
          <DialogTitle style={{ fontFamily: "inherit" }}>
            {busy
              ? h("מזהים את הארוחה", "Analyzing meal")
              : h("צילום ארוחה", "Photograph meal")}
          </DialogTitle>
        </header>
        <div
          hidden={!!preview}
          className="health-camera-frame"
          style={{ zIndex: 1 }}
          aria-hidden="true"
        />
        <footer style={{ zIndex: 1 }}>
          {noCamera && (
            <p>
              {h(
                "המצלמה אינה זמינה. אפשר לבחור תמונה.",
                "Camera unavailable. Choose a photo.",
              )}
            </p>
          )}
          {!busy && !availability.ready && <AiConsent />}
          {busy && (
            <div
              className="health-capture-progress"
              role="progressbar"
              aria-live="polite"
              aria-label={h("פענוח הארוחה", "Meal analysis")}
              aria-valuetext={
                phase === "upload"
                  ? h("מעלים תמונה", "Uploading photo")
                  : phase === "analysis"
                    ? h(
                        "מזהים מרכיבים וכמויות",
                        "Identifying foods and portions",
                      )
                    : h("שומרים ביומן", "Saving to diary")
              }
            >
              <ol>
                {(["upload", "analysis", "save"] as const).map(
                  (step, index) => {
                    const active = phase === step,
                      done =
                        index < ["upload", "analysis", "save"].indexOf(phase);
                    return (
                      <li key={step} data-active={active} data-done={done}>
                        {done ? (
                          <Check size={16} />
                        ) : active ? (
                          <LoaderCircle
                            size={16}
                            className="health-capture-spinner"
                          />
                        ) : (
                          <span className="health-capture-dot" />
                        )}
                        {step === "upload"
                          ? h("העלאה", "Upload")
                          : step === "analysis"
                            ? h("זיהוי", "Analyze")
                            : h("שמירה", "Save")}
                      </li>
                    );
                  },
                )}
              </ol>
              <strong>
                {phase === "upload"
                  ? h("מעלים את התמונה…", "Uploading your photo…")
                  : phase === "analysis"
                    ? h(
                        "מזהים מרכיבים וכמויות…",
                        "Identifying foods and portions…",
                      )
                    : h(
                        "מוסיפים את הארוחה ליומן…",
                        "Adding your meal to the diary…",
                      )}
              </strong>
            </div>
          )}

          {!busy && (
            <p>
              {h(
                "הארוחה תתווסף כהערכה. אפשר לתקן ביומן.",
                "Added as an estimate. Correct it in your diary.",
              )}
            </p>
          )}
          {!busy && (
            <p>
              {h(
                "התמונה תישמר ביומן האישי עם הארוחה.",
                "The photo is saved with the meal in your private diary.",
              )}
            </p>
          )}
          {error && (
            <div>
              {noFood ? (
                <p role="alert">
                  {h(
                    "לא זוהה אוכל בתמונה. נסו צילום קרוב וברור יותר.",
                    "No food identified. Try a clearer, closer photo.",
                  )}
                </p>
              ) : (
                <ErrorText error={error} />
              )}
              {!noFood && (
                <button disabled={busy} onClick={() => void submit()}>
                  {h("ניסיון נוסף", "Retry")}
                </button>
              )}
            </div>
          )}
          {!busy && (
            <div className="health-camera-actions">
              <button
                disabled={busy || !availability.ready}
                onClick={() => gallery.current?.click()}
              >
                {h("גלריה", "Gallery")}
              </button>
              {preview ? (
                <button
                  onClick={() => {
                    setPreview(null);
                    setCameraReady(false);
                    setError("");
                    setNoFood(false);
                    attempt.current = null;
                  }}
                >
                  {h("צילום חדש", "Retake photo")}
                </button>
              ) : (
                <button
                  className="health-camera-shutter"
                  disabled={
                    busy || noCamera || !cameraReady || !availability.ready
                  }
                  onClick={capture}
                  aria-label={h("צילום", "Take photo")}
                />
              )}
              <span />
            </div>
          )}
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

"use client";
import { useEffect, useRef, useState } from "react";
import {
  startBarcodeCamera,
  type IScannerControls,
} from "@/lib/camera/barcode";
import { useHealthText } from "@/lib/health/i18n";
export function BarcodeCamera({ onCode }: { onCode: (code: string) => void }) {
  const video = useRef<HTMLVideoElement>(null);
  const callback = useRef(onCode);
  const [error, setError] = useState(false);
  const h = useHealthText();
  useEffect(() => {
    callback.current = onCode;
  }, [onCode]);
  useEffect(() => {
    let cancelled = false,
      scanned = false;
    let controls: IScannerControls | undefined;
    if (video.current)
      void startBarcodeCamera(video.current, (code) => {
        if (cancelled || scanned) return;
        scanned = true;
        callback.current(code);
        controls?.stop();
      })
        .then((c) => {
          if (cancelled) c.stop();
          else controls = c;
        })
        .catch(() => {
          if (!cancelled) setError(true);
        });
    return () => {
      cancelled = true;
      controls?.stop();
    };
  }, []);
  return (
    <div>
      {error ? (
        <p role="alert">
          {h(
            "אין גישה למצלמה. אפשר להקליד את הברקוד.",
            "Camera unavailable. Enter the barcode manually.",
          )}
        </p>
      ) : (
        <video
          ref={video}
          autoPlay
          playsInline
          muted
          aria-label={h("סריקת ברקוד", "Barcode scanner")}
          className="max-h-64 w-full rounded-xl bg-black object-cover"
        />
      )}
    </div>
  );
}

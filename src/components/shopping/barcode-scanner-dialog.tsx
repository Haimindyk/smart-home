"use client";

import { useEffect, useRef, useState } from "react";
import { BrowserMultiFormatReader, type IScannerControls } from "@zxing/browser";
import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { toast } from "sonner";

/**
 * Open Food Facts is a free, keyless, community-run product database keyed
 * by barcode (EAN/UPC) — good enough coverage for groceries to turn a scan
 * into a real product name instead of a bare number. Best-effort only: any
 * failure (offline, unknown barcode, rate limit) just falls back to the
 * barcode itself as the item title.
 */
async function lookupProductName(barcode: string): Promise<string | null> {
  try {
    const res = await fetch(
      `https://world.openfoodfacts.org/api/v2/product/${barcode}.json?fields=product_name,product_name_he`,
      { signal: AbortSignal.timeout(5000) }
    );
    if (!res.ok) return null;
    const data = await res.json();
    if (data.status !== 1) return null;
    return data.product?.product_name_he || data.product?.product_name || null;
  } catch {
    return null;
  }
}

export function BarcodeScannerDialog({
  open,
  onOpenChange,
  sectionId,
  createdBy,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  sectionId: string;
  createdBy: string | null;
}) {
  const createTask = useAppStore((s) => s.createTask);
  const t = useT();
  // A plain useRef read inside an effect keyed on `open` is unreliable here:
  // Base UI's Dialog.Popup (like Radix/MUI dialogs) doesn't mount its
  // children synchronously the instant `open` flips true — it controls
  // mount timing to support open/close animations — so the effect could
  // run before this <video> was actually attached, get `undefined`, and
  // have zxing scan into its own invisible internal element while ours
  // sat there empty forever. The ref itself stays a plain mutable handle
  // (DOM nodes are meant to be mutated directly); `videoMounted` is a
  // separate signal purely so the effect's dependency array notices once
  // the callback ref actually fires and re-runs at the right time.
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const [videoMounted, setVideoMounted] = useState(false);
  const [status, setStatus] = useState<"scanning" | "looking-up" | "error">("scanning");
  const [errorDetail, setErrorDetail] = useState<string | null>(null);
  // Temporary on-screen diagnostics while tracking down the black-preview
  // bug — shows real stream/video state instead of guessing blindly.
  // Split in two: `liveState` is overwritten every tick (element/track
  // state right now), `log` only ever grows (one-time lifecycle events) —
  // combining them into one field let the periodic tick wipe out the
  // lifecycle messages before they could be read.
  const [liveState, setLiveState] = useState<string>("");
  const [log, setLog] = useState<string[]>([]);
  // Reset to "scanning" each time the dialog opens — adjusting state during
  // render per https://react.dev/learn/you-might-not-need-an-effect#adjusting-some-state-when-a-prop-changes
  const [syncedOpen, setSyncedOpen] = useState(open);
  if (open !== syncedOpen) {
    setSyncedOpen(open);
    if (open) {
      setStatus("scanning");
      setErrorDetail(null);
    }
  }

  useEffect(() => {
    if (!open || !videoRef.current) return;

    let cancelled = false;
    let busy = false;
    let lastCode: string | null = null;
    let controls: IScannerControls | null = null;
    const reader = new BrowserMultiFormatReader();

    async function handleScanned(code: string) {
      busy = true;
      setStatus("looking-up");
      const name = await lookupProductName(code);
      if (cancelled) return;
      void createTask({
        sectionId,
        title: name ?? code,
        createdBy,
        extra: { notes: `${t("scannedBarcode")}: ${code}` },
      });
      toast(`${t("addedFromBarcode")}: ${name ?? code}`);
      setStatus("scanning");
      // Give the same item a moment before it can be re-scanned/re-added.
      setTimeout(() => {
        lastCode = null;
        busy = false;
      }, 2000);
    }

    const video = videoRef.current;
    // zxing's internal video setup calls videoElement.setAttribute('muted',
    // 'true') rather than assigning the DOM property — WebKit's autoplay
    // gate reads the live `.muted` property, which setAttribute doesn't
    // reliably update once the element is already mounted. Set it directly
    // ourselves so the stream is genuinely muted before playback starts.
    video.muted = true;
    video.defaultMuted = true;

    const addLog = (entry: string) => setLog((prev) => [...prev, entry]);
    const updateDebug = () => {
      if (!video) return;
      const stream = video.srcObject as MediaStream | null;
      const tracks = stream?.getVideoTracks() ?? [];
      const trackInfo = tracks.length
        ? tracks.map((tr) => `state=${tr.readyState} enabled=${tr.enabled} muted=${tr.muted} label=${tr.label}`).join(" | ")
        : "none";
      setLiveState(
        `readyState=${video.readyState} size=${video.videoWidth}x${video.videoHeight} paused=${video.paused} muted=${video.muted} networkState=${video.networkState} srcObject=${stream ? "set" : "null"} tracks=[${trackInfo}]`
      );
    };
    const events = ["loadedmetadata", "loadeddata", "playing", "play", "pause", "stalled", "suspend", "error", "emptied"] as const;
    events.forEach((ev) => video?.addEventListener(ev, updateDebug));
    const debugInterval = setInterval(updateDebug, 500);

    addLog("calling decodeFromConstraints...");

    reader
      .decodeFromConstraints(
        { video: { facingMode: { ideal: "environment" } } },
        video,
        (result) => {
          if (cancelled || busy || !result) return;
          const code = result.getText();
          if (code === lastCode) return;
          lastCode = code;
          void handleScanned(code);
        }
      )
      .then((c) => {
        if (cancelled) {
          c.stop();
          return;
        }
        controls = c;
        addLog("decodeFromConstraints resolved");
        updateDebug();
        // Belt-and-suspenders: iOS Safari can silently swallow the
        // script-driven play() zxing issues internally if the async
        // getUserMedia permission prompt consumed the tap's user-activation
        // window by the time it runs — the stream attaches but the video
        // never actually starts, showing as a black square. The `autoPlay`
        // attribute on the element covers most cases; retrying here is a
        // harmless no-op if it's already playing.
        video?.play().then(
          () => addLog("play() resolved"),
          (err) => addLog(`play() rejected: ${err?.name}: ${err?.message}`)
        );
      })
      .catch((err) => {
        addLog(`decodeFromConstraints rejected: ${err?.name}: ${err?.message}`);
        if (cancelled) return;
        setStatus("error");
        setErrorDetail(`${err?.name ?? "Error"}: ${err?.message ?? String(err)}`);
      });

    return () => {
      cancelled = true;
      controls?.stop();
      events.forEach((ev) => video?.removeEventListener(ev, updateDebug));
      clearInterval(debugInterval);
    };
    // `t` from useT() is a brand-new function every render (never
    // memoized) — including it here caused the effect to tear down and
    // restart the camera stream on every single state update this effect
    // itself made (an infinite loop: state update -> re-render -> new `t`
    // -> effect re-runs -> more state updates -> ...), which is exactly
    // why the stream never stabilized long enough to render a frame.
    // `createTask` is stable (bound once by zustand) but doesn't need to
    // restart scanning either; both are read via closure instead.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, videoMounted, sectionId, createdBy]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm" blurOverlay={false}>
        <DialogHeader>
          <DialogTitle>{t("scanBarcode")}</DialogTitle>
        </DialogHeader>
        <div className="relative overflow-hidden rounded-xl bg-black">
          <video
            ref={(el) => {
              videoRef.current = el;
              setVideoMounted(!!el);
            }}
            className="aspect-square w-full object-cover"
            autoPlay
            muted
            playsInline
          />
          <div className="pointer-events-none absolute inset-8 rounded-lg border-2 border-white/70" />
          {status === "looking-up" && (
            <div className="absolute inset-0 flex items-center justify-center bg-black/50 text-sm text-white">
              {t("lookingUpProduct")}
            </div>
          )}
          {status === "error" && (
            <div className="absolute inset-0 flex flex-col items-center justify-center gap-1 bg-black/70 p-4 text-center text-sm text-white">
              <span>{t("cameraUnavailable")}</span>
              {errorDetail && <span className="text-xs opacity-80" dir="ltr">{errorDetail}</span>}
            </div>
          )}
        </div>
        <p className="text-center text-xs text-muted-foreground">{t("scanBarcodeHint")}</p>
        {(log.length > 0 || liveState) && (
          <div dir="ltr" className="flex flex-col gap-1 break-all rounded bg-muted p-2 text-[10px] text-muted-foreground">
            {log.map((entry, i) => (
              <div key={i}>{entry}</div>
            ))}
            {liveState && <div className="font-semibold">{liveState}</div>}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

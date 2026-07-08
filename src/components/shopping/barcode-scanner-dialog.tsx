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
  const videoRef = useRef<HTMLVideoElement>(null);
  const [status, setStatus] = useState<"scanning" | "looking-up" | "error">("scanning");
  // Reset to "scanning" each time the dialog opens — adjusting state during
  // render per https://react.dev/learn/you-might-not-need-an-effect#adjusting-some-state-when-a-prop-changes
  const [syncedOpen, setSyncedOpen] = useState(open);
  if (open !== syncedOpen) {
    setSyncedOpen(open);
    if (open) setStatus("scanning");
  }

  useEffect(() => {
    if (!open) return;

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

    // zxing's internal video setup calls videoElement.setAttribute('muted',
    // 'true') rather than assigning the DOM property — WebKit's autoplay
    // gate reads the live `.muted` property, which setAttribute doesn't
    // reliably update once the element is already mounted. Set it directly
    // ourselves so the stream is genuinely muted before playback starts.
    if (videoRef.current) {
      videoRef.current.muted = true;
      videoRef.current.defaultMuted = true;
    }

    reader
      .decodeFromConstraints(
        { video: { facingMode: { ideal: "environment" } } },
        videoRef.current ?? undefined,
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
        // Belt-and-suspenders: iOS Safari can silently swallow the
        // script-driven play() zxing issues internally if the async
        // getUserMedia permission prompt consumed the tap's user-activation
        // window by the time it runs — the stream attaches but the video
        // never actually starts, showing as a black square. The `autoPlay`
        // attribute on the element covers most cases; retrying here is a
        // harmless no-op if it's already playing.
        void videoRef.current?.play().catch(() => {});
      })
      .catch(() => {
        if (!cancelled) setStatus("error");
      });

    return () => {
      cancelled = true;
      controls?.stop();
    };
  }, [open, sectionId, createdBy, createTask, t]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>{t("scanBarcode")}</DialogTitle>
        </DialogHeader>
        <div className="relative overflow-hidden rounded-xl bg-black">
          <video
            ref={(el) => {
              videoRef.current = el;
              if (el) {
                el.muted = true;
                el.defaultMuted = true;
              }
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
            <div className="absolute inset-0 flex items-center justify-center bg-black/70 p-4 text-center text-sm text-white">
              {t("cameraUnavailable")}
            </div>
          )}
        </div>
        <p className="text-center text-xs text-muted-foreground">{t("scanBarcodeHint")}</p>
      </DialogContent>
    </Dialog>
  );
}

"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { BrowserMultiFormatReader, type IScannerControls } from "@zxing/browser";
import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import { createClient } from "@/lib/supabase/client";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { sortByPosition } from "@/lib/ordering/rank";
import { toast } from "sonner";

/** Names the family has already taught the app for a barcode — checked
 * before any external lookup, so once anyone identifies a product (most
 * commonly Israeli-local ones Open Food Facts doesn't know), every family
 * member gets automatic recognition on every future scan of that barcode. */
async function lookupTaughtProductName(barcode: string): Promise<string | null> {
  const supabase = createClient();
  const { data } = await supabase
    .from("barcode_products")
    .select("product_name")
    .eq("barcode", barcode)
    .maybeSingle();
  return data?.product_name ?? null;
}

async function rememberProductName(barcode: string, productName: string, createdBy: string | null) {
  const supabase = createClient();
  await supabase.from("barcode_products").upsert({ barcode, product_name: productName, created_by: createdBy });
}

/**
 * Open Food Facts and its sister project Open Products Facts are free,
 * keyless, community-run product databases keyed by barcode (EAN/UPC) — the
 * former for groceries, the latter for everything else (household,
 * cosmetics, electronics...) a shopping list also ends up containing.
 * Best-effort only: any failure (offline, unknown barcode, rate limit) just
 * moves on to the next source.
 */
async function lookupFromOpenFactsSite(host: string, barcode: string): Promise<string | null> {
  try {
    const res = await fetch(
      `https://${host}/api/v2/product/${barcode}.json?fields=product_name,product_name_he`,
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

async function lookupProductName(barcode: string): Promise<string | null> {
  const taught = await lookupTaughtProductName(barcode);
  if (taught) return taught;
  const food = await lookupFromOpenFactsSite("world.openfoodfacts.org", barcode);
  if (food) return food;
  return lookupFromOpenFactsSite("world.openproductsfacts.org", barcode);
}

export function BarcodeScannerDialog({
  open,
  onOpenChange,
  sectionId,
  createdBy,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Fixed target list (e.g. opened from that section's own quick-add). If
   * omitted (e.g. opened from the header), the user picks from the
   * available shopping-kind sections instead. */
  sectionId?: string;
  createdBy: string | null;
}) {
  const createTask = useAppStore((s) => s.createTask);
  const sections = useAppStore((s) => s.sections);
  const t = useT();

  const shoppingSections = useMemo(
    () => sortByPosition(Object.values(sections).filter((s) => s.kind === "shopping" && !s.deleted_at)),
    [sections]
  );

  const [pickedSectionId, setPickedSectionId] = useState<string | null>(null);
  const targetSectionId = sectionId ?? pickedSectionId ?? shoppingSections[0]?.id ?? null;

  // A plain useRef read inside an effect keyed on `open` is unreliable here:
  // Base UI's Dialog.Popup (like Radix/MUI dialogs) doesn't mount its
  // children synchronously the instant `open` flips true — it controls
  // mount timing to support open/close animations — so the effect could
  // run before this <video> was actually attached. `videoMounted` is a
  // separate signal purely so the effect's dependency array notices once
  // the callback ref actually fires and re-runs at the right time.
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const [videoMounted, setVideoMounted] = useState(false);
  const [status, setStatus] = useState<"scanning" | "looking-up" | "naming" | "error">("scanning");
  const [pendingCode, setPendingCode] = useState<string | null>(null);
  const [manualName, setManualName] = useState("");
  // Scan-loop bookkeeping lives in refs (not effect-local `let`s) so the
  // "naming" form below — rendered outside the effect — can resume
  // scanning once the person confirms or skips a name.
  const busyRef = useRef(false);
  const lastCodeRef = useRef<string | null>(null);
  // Reset to "scanning" each time the dialog opens — adjusting state during
  // render per https://react.dev/learn/you-might-not-need-an-effect#adjusting-some-state-when-a-prop-changes
  const [syncedOpen, setSyncedOpen] = useState(open);
  if (open !== syncedOpen) {
    setSyncedOpen(open);
    if (open) {
      setStatus("scanning");
      setPendingCode(null);
      setManualName("");
    }
  }

  function resumeScanning() {
    // Give the same item a moment before it can be re-scanned/re-added.
    setTimeout(() => {
      lastCodeRef.current = null;
      busyRef.current = false;
    }, 2000);
  }

  function addItem(code: string, name: string | null) {
    if (!targetSectionId) return;
    void createTask({
      sectionId: targetSectionId,
      title: name ?? code,
      createdBy,
      extra: { notes: `${t("scannedBarcode")}: ${code}` },
    });
    toast(`${t("addedFromBarcode")}: ${name ?? code}`);
    setStatus("scanning");
    setPendingCode(null);
    resumeScanning();
  }

  function confirmManualName() {
    if (!pendingCode) return;
    const name = manualName.trim();
    if (name) void rememberProductName(pendingCode, name, createdBy);
    addItem(pendingCode, name || null);
  }

  useEffect(() => {
    if (!open || !videoRef.current || !targetSectionId) return;

    // Starting a fresh camera stream means a fresh scanning session.
    busyRef.current = false;
    lastCodeRef.current = null;

    let cancelled = false;
    let controls: IScannerControls | null = null;
    const reader = new BrowserMultiFormatReader();

    async function handleScanned(code: string) {
      busyRef.current = true;
      setStatus("looking-up");
      const name = await lookupProductName(code);
      if (cancelled) return;
      // Open Food Facts has thin coverage for Israeli-local products (729-
      // prefixed barcodes) — rather than silently filing the raw barcode
      // number as the item's title, let the person type the real name in.
      if (!name) {
        setPendingCode(code);
        setManualName("");
        setStatus("naming");
        return;
      }
      addItem(code, name);
    }

    const video = videoRef.current;
    // zxing's internal video setup calls videoElement.setAttribute('muted',
    // 'true') rather than assigning the DOM property — WebKit's autoplay
    // gate reads the live `.muted` property, which setAttribute doesn't
    // reliably update once the element is already mounted. Set it directly
    // ourselves so the stream is genuinely muted before playback starts.
    video.muted = true;
    video.defaultMuted = true;

    reader
      .decodeFromConstraints(
        { video: { facingMode: { ideal: "environment" } } },
        video,
        (result) => {
          if (cancelled || busyRef.current || !result) return;
          const code = result.getText();
          if (code === lastCodeRef.current) return;
          lastCodeRef.current = code;
          void handleScanned(code);
        }
      )
      .then((c) => {
        if (cancelled) {
          c.stop();
          return;
        }
        controls = c;
        void video.play();
      })
      .catch(() => {
        if (!cancelled) setStatus("error");
      });

    return () => {
      cancelled = true;
      controls?.stop();
    };
    // `t` from useT() is a brand-new function every render (never
    // memoized) — including it here would tear down and restart the
    // camera stream on every unrelated re-render. `createTask`/`addItem`
    // don't need to restart scanning either; all are read via closure.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, videoMounted, targetSectionId, createdBy]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm" blurOverlay={false}>
        <DialogHeader>
          <DialogTitle>{t("scanBarcode")}</DialogTitle>
        </DialogHeader>

        {!sectionId && shoppingSections.length > 1 && (
          <div className="grid gap-2">
            <Label>{t("section_shopping")}</Label>
            <Select
              value={targetSectionId ?? undefined}
              onValueChange={(v) => v && setPickedSectionId(v)}
            >
              <SelectTrigger>
                <SelectValue>{(v: string) => sections[v] ? `${sections[v].emoji ?? ""} ${sections[v].name}` : v}</SelectValue>
              </SelectTrigger>
              <SelectContent>
                {shoppingSections.map((s) => (
                  <SelectItem key={s.id} value={s.id}>
                    {s.emoji} {s.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        )}

        {!targetSectionId ? (
          <p className="py-4 text-center text-sm text-muted-foreground">{t("noShoppingListYet")}</p>
        ) : (
          <>
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
                <div className="absolute inset-0 flex items-center justify-center bg-black/70 p-4 text-center text-sm text-white">
                  {t("cameraUnavailable")}
                </div>
              )}
            </div>
            {status === "naming" ? (
              <form
                className="flex flex-col gap-2"
                onSubmit={(e) => {
                  e.preventDefault();
                  confirmManualName();
                }}
              >
                <p className="text-center text-xs text-muted-foreground">{t("productNotRecognized")}</p>
                <Input
                  autoFocus
                  dir="auto"
                  value={manualName}
                  onChange={(e) => setManualName(e.target.value)}
                  placeholder={t("productNamePlaceholder")}
                />
                <div className="flex gap-2">
                  <Button type="button" variant="outline" className="flex-1" onClick={() => confirmManualName()}>
                    {t("addWithoutName")}
                  </Button>
                  <Button type="submit" className="flex-1" disabled={!manualName.trim()}>
                    {t("add")}
                  </Button>
                </div>
              </form>
            ) : (
              <p className="text-center text-xs text-muted-foreground">{t("scanBarcodeHint")}</p>
            )}
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}

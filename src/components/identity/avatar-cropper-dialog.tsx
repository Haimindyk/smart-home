"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { useT } from "@/lib/i18n/store";

const VIEWPORT_SIZE = 260;
const OUTPUT_SIZE = 512;
const MAX_ZOOM = 4;

/**
 * Lets the user pan/zoom a just-picked photo inside a circular viewport
 * before it's uploaded, so the crop actually centers their face instead of
 * whatever the raw photo happened to frame. Exports a square JPEG blob —
 * the circular look everywhere it's displayed comes from MemberAvatar's
 * own `rounded-full` styling, so the export itself just needs to be the
 * correctly-cropped square region, not literally circular pixels.
 */
export function AvatarCropperDialog({
  file,
  onCancel,
  onCropped,
}: {
  file: File | null;
  onCancel: () => void;
  onCropped: (blob: Blob) => void;
}) {
  const t = useT();
  const imgRef = useRef<HTMLImageElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const dragState = useRef<{
    startX: number;
    startY: number;
    startOffsetX: number;
    startOffsetY: number;
  } | null>(null);

  const [imageUrl, setImageUrl] = useState<string | null>(null);
  const [naturalSize, setNaturalSize] = useState<{
    w: number;
    h: number;
  } | null>(null);
  const [zoom, setZoom] = useState(1);
  const [offset, setOffset] = useState({ x: 0, y: 0 });

  // Reset everything when a new file comes in (or the dialog is closed) —
  // adjusting state during render per
  // https://react.dev/learn/you-might-not-need-an-effect#adjusting-some-state-when-a-prop-changes
  const [syncedFile, setSyncedFile] = useState(file);
  if (file !== syncedFile) {
    setSyncedFile(file);
    setImageUrl(file ? URL.createObjectURL(file) : null);
    setNaturalSize(null);
    setZoom(1);
    setOffset({ x: 0, y: 0 });
  }

  // Revoking is a genuine external-system side effect (not state sync), so
  // it stays in an effect — separate from the render-time reset above.
  useEffect(() => {
    return () => {
      if (imageUrl) URL.revokeObjectURL(imageUrl);
    };
  }, [imageUrl]);

  const baseScale = useMemo(() => {
    if (!naturalSize) return 1;
    return VIEWPORT_SIZE / Math.min(naturalSize.w, naturalSize.h);
  }, [naturalSize]);

  const displayed = useMemo(() => {
    if (!naturalSize) return { w: VIEWPORT_SIZE, h: VIEWPORT_SIZE };
    const scale = baseScale * zoom;
    return { w: naturalSize.w * scale, h: naturalSize.h * scale };
  }, [naturalSize, baseScale, zoom]);

  function clampOffset(
    x: number,
    y: number,
    forDisplayed: { w: number; h: number },
  ) {
    const maxX = Math.max(0, (forDisplayed.w - VIEWPORT_SIZE) / 2);
    const maxY = Math.max(0, (forDisplayed.h - VIEWPORT_SIZE) / 2);
    return {
      x: Math.min(maxX, Math.max(-maxX, x)),
      y: Math.min(maxY, Math.max(-maxY, y)),
    };
  }

  function handlePointerDown(e: React.PointerEvent) {
    (e.target as Element).setPointerCapture(e.pointerId);
    dragState.current = {
      startX: e.clientX,
      startY: e.clientY,
      startOffsetX: offset.x,
      startOffsetY: offset.y,
    };
  }

  function handlePointerMove(e: React.PointerEvent) {
    if (!dragState.current) return;
    const dx = e.clientX - dragState.current.startX;
    const dy = e.clientY - dragState.current.startY;
    setOffset(
      clampOffset(
        dragState.current.startOffsetX + dx,
        dragState.current.startOffsetY + dy,
        displayed,
      ),
    );
  }

  function handlePointerUp() {
    dragState.current = null;
  }

  function handleWheel(e: React.WheelEvent) {
    e.preventDefault();
    setZoom((z) => Math.min(MAX_ZOOM, Math.max(1, z - e.deltaY * 0.002)));
  }

  function handleZoomChange(next: number) {
    setZoom(next);
    setOffset((o) => {
      if (!naturalSize) return o;
      const scale = baseScale * next;
      return clampOffset(o.x, o.y, {
        w: naturalSize.w * scale,
        h: naturalSize.h * scale,
      });
    });
  }

  function confirm() {
    const img = imgRef.current;
    if (!img || !naturalSize) return;
    const canvas = document.createElement("canvas");
    canvas.width = OUTPUT_SIZE;
    canvas.height = OUTPUT_SIZE;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const ratio = OUTPUT_SIZE / VIEWPORT_SIZE;
    const left = VIEWPORT_SIZE / 2 - displayed.w / 2 + offset.x;
    const top = VIEWPORT_SIZE / 2 - displayed.h / 2 + offset.y;
    ctx.drawImage(
      img,
      0,
      0,
      naturalSize.w,
      naturalSize.h,
      left * ratio,
      top * ratio,
      displayed.w * ratio,
      displayed.h * ratio,
    );

    canvas.toBlob(
      (blob) => {
        if (blob) onCropped(blob);
      },
      "image/jpeg",
      0.92,
    );
  }

  return (
    <Dialog open={!!file} onOpenChange={(open) => !open && onCancel()}>
      <DialogContent className="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle>{t("cropPhoto")}</DialogTitle>
        </DialogHeader>

        <div className="flex flex-col items-center gap-4 py-2">
          <div
            ref={containerRef}
            className="relative overflow-hidden rounded-full bg-muted ring-2 ring-border touch-none select-none"
            style={{
              width: VIEWPORT_SIZE,
              height: VIEWPORT_SIZE,
              cursor: "grab",
            }}
            onPointerDown={handlePointerDown}
            onPointerMove={handlePointerMove}
            onPointerUp={handlePointerUp}
            onPointerCancel={handlePointerUp}
            onWheel={handleWheel}
          >
            {imageUrl && (
              // eslint-disable-next-line @next/next/no-img-element -- cropper needs raw pixel control for canvas export
              <img
                ref={imgRef}
                src={imageUrl}
                alt=""
                draggable={false}
                onLoad={(e) => {
                  const el = e.currentTarget;
                  setNaturalSize({ w: el.naturalWidth, h: el.naturalHeight });
                }}
                style={{
                  position: "absolute",
                  width: displayed.w,
                  height: displayed.h,
                  left: VIEWPORT_SIZE / 2 - displayed.w / 2 + offset.x,
                  top: VIEWPORT_SIZE / 2 - displayed.h / 2 + offset.y,
                  maxWidth: "none",
                }}
              />
            )}
          </div>

          <input
            type="range"
            min={1}
            max={MAX_ZOOM}
            step={0.01}
            value={zoom}
            onChange={(e) => handleZoomChange(Number(e.target.value))}
            className="w-full accent-primary"
            aria-label={t("zoom")}
          />
        </div>

        <DialogFooter>
          <Button type="button" variant="outline" onClick={onCancel}>
            {t("cancel")}
          </Button>
          <Button type="button" onClick={confirm} disabled={!naturalSize}>
            {t("save")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

import {
  BrowserMultiFormatReader,
  type IScannerControls,
} from "@zxing/browser";
export type { IScannerControls };
export function startBarcodeCamera(
  video: HTMLVideoElement,
  onCode: (code: string) => void,
): Promise<IScannerControls> {
  video.muted = true;
  video.defaultMuted = true;
  return new BrowserMultiFormatReader().decodeFromConstraints(
    { video: { facingMode: { ideal: "environment" } } },
    video,
    (result) => {
      if (result) onCode(result.getText());
    },
  );
}

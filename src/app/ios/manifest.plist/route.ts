import { iosManifestXml } from "@/lib/pwa/ios-app";

// iOS only installs over the air from HTTPS, so the IPA URL is built from the origin this request arrived on.
export async function GET(request: Request) {
  const origin = new URL(request.url).origin;
  return new Response(iosManifestXml(origin), {
    headers: { "Content-Type": "text/xml; charset=utf-8", "Cache-Control": "no-store" },
  });
}

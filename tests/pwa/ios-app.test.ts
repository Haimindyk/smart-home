import { describe, expect, it } from "vitest";
import { IOS_APP, iosInstallUrl, iosManifestXml } from "../../src/lib/pwa/ios-app";

describe("over-the-air iPhone app install", () => {
  it("builds the itms-services link from the site origin", () => {
    expect(iosInstallUrl("https://kh.example.com")).toBe(
      "itms-services://?action=download-manifest&url=https%3A%2F%2Fkh.example.com%2Fios%2Fmanifest.plist",
    );
  });
  it("writes a manifest that points at the IPA on the same origin with the app's bundle id", () => {
    const xml = iosManifestXml("https://kh.example.com");
    expect(xml).toContain("<string>https://kh.example.com/ios/SmartHomeWellness.ipa</string>");
    expect(xml).toContain(`<string>${IOS_APP.bundleId}</string>`);
    expect(xml).toContain("software-package");
  });
  it("escapes characters that would break the property list", () => {
    expect(iosManifestXml("https://a.test/?x=1&y=<2>")).toContain("&amp;y=&lt;2&gt;");
  });
});

/**
 * The native iPhone app, installed over the air from this site (ad-hoc build, no App Store).
 * public/ios/SmartHomeWellness.ipa is replaced by scripts/update-ios-ipa.sh; keep version/build in sync with it.
 * An ad-hoc build installs only on iPhones registered in the Apple developer account's provisioning profile.
 */
export const IOS_APP = {
  bundleId: "com.haimindyk.smarthome.wellness",
  title: "Wellness",
  version: "0.1.0",
  build: "119",
  ipaPath: "/ios/SmartHomeWellness.ipa",
  manifestPath: "/ios/manifest.plist",
} as const;

/** The itms-services link iOS Safari understands: it downloads the manifest and offers to install the app. */
export function iosInstallUrl(origin: string) {
  return `itms-services://?action=download-manifest&url=${encodeURIComponent(origin + IOS_APP.manifestPath)}`;
}

/** The over-the-air install manifest (an Apple property list) for the given site origin. */
export function iosManifestXml(origin: string) {
  const esc = (v: string) => v.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key><string>software-package</string>
          <key>url</key><string>${esc(origin + IOS_APP.ipaPath)}</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key><string>${esc(IOS_APP.bundleId)}</string>
        <key>bundle-version</key><string>${esc(IOS_APP.version)}</string>
        <key>kind</key><string>software</string>
        <key>title</key><string>${esc(IOS_APP.title)}</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
`;
}

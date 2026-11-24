#!/usr/bin/env bash
# Replace the over-the-air iPhone app served by the website with the ad-hoc IPA from a CI run.
# Usage: scripts/update-ios-ipa.sh <run-id>   (a "Native iOS checks" run whose adhoc-ipa artifact has not expired)
# Then commit public/ios/SmartHomeWellness.ipa and src/lib/pwa/ios-app.ts in a pull request.
set -euo pipefail
run="${1:?usage: update-ios-ipa.sh <run-id>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
gh run download "$run" --name adhoc-ipa --dir "$work"
ipa="$work/SmartHomeWellness.ipa"
[ -f "$ipa" ] || { echo "no SmartHomeWellness.ipa in the artifact" >&2; exit 1; }
unzip -q "$ipa" -d "$work/x"
plist="$(echo "$work"/x/Payload/*.app/Info.plist)"
version="$(plutil -extract CFBundleShortVersionString raw "$plist")"
build="$(plutil -extract CFBundleVersion raw "$plist")"
cp "$ipa" "$root/public/ios/SmartHomeWellness.ipa"
sed -i '' -E "s/^  version: \".*\",/  version: \"$version\",/; s/^  build: \".*\",/  build: \"$build\",/" "$root/src/lib/pwa/ios-app.ts"
echo "Updated to $version ($build)"

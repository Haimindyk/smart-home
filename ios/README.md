# Native iOS companion — first milestone

A SwiftUI iPhone application (iOS 17+) using the **same account, PIN login and
private database** as the existing app. This is native SwiftUI + HealthKit;
there is no web view and no replacement backend.

## Implemented

- Existing four-digit PIN endpoint; verified Supabase user/member binding.
- Session in device-only, unlocked-device Keychain; rotating refresh tokens;
  sign out revokes only this device's session. The PIN is never persisted.
- Hebrew RTL Today screen, visible month/year, date picker/week navigation,
  calorie and macro progress from real meals/goals. No water tracking.
- Existing meal details and private meal/product photos (short-lived signed URLs,
  memory-only networking), existing training plans and workout history.
- Read permission for workouts, steps, active energy and supported distances.
  Query up to 500 workouts from the last 30 days; preview and explicitly select
  before uploading. Today's aggregated steps stay on the device.
- Owner-scoped deterministic UUIDv8 (SHA-256) import IDs, source UUID deduplication,
  retry-safe inserts and version-checked deletion/restoration. No inferred sets,
  repetitions or energy when Apple has no value. No calorie-goal adjustment.
- Privacy sheet explaining exactly which selected data reaches the existing
  backend; opaque app-switcher cover. No HealthKit writes/background sync.
- Web model retains imported metadata when opening/editing a session, and the
  web workout list identifies Apple Health imports with their duration.

**This milestone does not yet replace every web workflow.** Creating/editing
meals, camera/AI corrections, barcode lookup, AI chat, building/executing training
plans, offline mutation queues and account deletion are still existing web
features; they have not been ported into these native screens. There is no
App Store/TestFlight release or verified physical-device HealthKit run yet.

## Build on a Mac

Use Xcode 16 or newer, its iOS Simulator runtime and XcodeGen >= 2.42.

```sh
brew install xcodegen
cp ios/App/Config/Local.xcconfig.example ios/App/Config/Local.xcconfig
```

In `Local.xcconfig` set `SUPABASE_PUBLIC_KEY` to the existing Supabase project's
**publishable key** (legacy anon key also works). The host is already configured
in `App.xcconfig`. Never use a secret/service-role key. Local configuration,
generated projects, signing settings and build output are ignored by Git.

```sh
cd ios/App
xcodegen generate
open SmartHomeWellness.xcodeproj
```

Select `SmartHomeWellness` and an iPhone Simulator. For a physical iPhone, set
`DEVELOPMENT_TEAM` locally, choose a bundle identifier your team can provision,
and enable HealthKit in the Apple app identifier. A public key is a client
identifier; database row ownership remains enforced by the existing RLS.

Unsigned simulator build (requires no production credentials/signing):

```sh
xcodebuild -project SmartHomeWellness.xcodeproj \
  -scheme SmartHomeWellness -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

The `Native iOS checks` PR workflow runs portable tests and this Xcode build on
macOS. It does not deploy an app/backend, sign for distribution or contact Health
with real user data. Configuration placeholders allow compilation; an actual
login requires the local public-key configuration above.

## Verification

```sh
swift test --package-path ios/Core
pnpm test
pnpm typecheck
```

Portable tests exercise existing PIN login, server-verified owner, refresh,
owner isolation, logout scope, source dedup, unknown measurements, timezone
validation and JSON round trips. HTTP is mocked. They do not prove an actual
user login, system authorization sheet or watch import.

Before TestFlight, verify on an iPhone with a real account: allow/deny individual
Health read types; empty Health store; recorded watch/phone workout; select only
one of several workouts; repeated import; interrupted request and retry; delete
and explicitly re-import; logout/account switch during read/import; foreground
refresh; timezone near midnight; large accessibility text and VoiceOver.
Confirm the same imported workout appears once on the web and deleting it never
changes the original Apple Health record. An external Apple development/signing
setup is necessary for device/distribution validation. Do not call this an
App Store-ready release until these checks and the missing native flows are done.

## Data contract

Selected workouts are inserted into `workout_sessions` as completed quick logs,
with existing required fields and `appleHealth` source metadata. Measurements are
seconds, meters and kilocalories; missing optional values remain JSON null.
Workout date follows the account timezone, while start/end preserve UTC instants.
No new schema migration, service key or privileged endpoint is required.
All reads/writes carry the verified user's bearer token and owner filter; RLS
remains authoritative. No medical archive is uploaded.

GitHub is the source of truth. All changes go through a PR; backend/web releases
remain consequences of a main merge. ## TestFlight

Merging a PR that touches `ios/**` into `main` runs `.github/workflows/ios-beta.yml`
on the self-hosted macOS runner: portable tests, `xcodegen generate`, signed archive
(automatic signing via App Store Connect API key) and upload to TestFlight through
`ios/fastlane` (`bundle exec fastlane beta`). Build number = GitHub run number;
bump `MARKETING_VERSION` in `ios/App/project.yml` for a new version. Required
`beta` environment secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_KEY`,
`APPLE_DEVELOPER_TEAM_ID`, `MACOS_KEYCHAIN_PASSWORD`, `SUPABASE_PUBLIC_KEY`.
One-time Apple setup: App ID `com.haimindyk.smarthome.wellness` with HealthKit
enabled and an App Store Connect app record. The icon in `Sources/Assets.xcassets` is a placeholder.

## Releases

Every merge to `main` that touches `ios/` uploads a new TestFlight build. If TestFlight lists a build that cannot be installed ("The app is not available or doesn't exist"), merge any change under `ios/` to produce a fresh build number; a re-run of the same workflow run reuses the same build number and Apple rejects the duplicate.

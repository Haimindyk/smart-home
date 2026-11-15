# Apple Watch and iPhone activity import

Research checked against Apple documentation on 2026-11-15. The current app is a
web/PWA app; there is no HealthKit bridge or completed import feature yet.

- Manual, free path: Health on iPhone → profile → Export All Health Data. Apple
  exports health/fitness data as XML. A browser importer can read the selected
  file locally, extract workouts only, preview a chosen date range and save after
  confirmation. It must not upload the whole health archive or medical records.
- Automatic path: an iOS companion using HealthKit, explicit read permissions,
  HKWorkout queries and incremental sync. This requires a native component;
  Safari/PWA does not obtain access by requesting a web permission.
- Start with workout type, start/end, duration, measured energy/distance and
  source. Treat Apple Watch and iPhone records as potentially overlapping;
  deduplicate by source UUID and do not infer strength sets/reps or double-count
  calories against an existing app workout. Retain original units and timezone.
- Neither an Apple subscription nor an AI model is needed for the manual XML
  importer. Native development/distribution is a separate implementation and
  account/cost decision; do not promise free App Store distribution.

Sources:
- https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios
- https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
- https://developer.apple.com/documentation/Xcode/configuring-healthkit-access

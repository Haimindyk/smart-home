# Optional private product photos

A packaged product can have an optional camera/gallery photo. It is compressed
and uploaded through the existing private health-images bucket, without AI or
nutrition-label inference. Adding a confirmed product remembers its photo and
confirmed unit size in personal foods. The selected amount stays separate.
Rescanning that barcode restores the saved photo; saved/recent food results and
meal cards can display it using short-lived owner-scoped signed URLs.

Food JSON retains imagePath; the additive owner trigger checks both top-level
and nested meal/recipe food paths. Maintenance and module deletion retain images
referenced by active foods/recipes/meals. Abandoned uploads follow the existing
24-hour orphan cleanup. Photos are not copied into the shared food catalog.
Water controls and targets were removed from the UI; old stored water records
were not destructively deleted. Legacy profile defaults remain wire-compatible.

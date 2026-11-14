# Reproducible photo model comparison

The operator-only `scripts/benchmark-wellness-photo.mjs` compares the current
Llama 3.2 vision stage with Gemma 4. The production provider, prompts, compact
schema, Hebrew normalization and cooking-oil validation are bundled from the
repository; the normalizer stays Llama 3.3 70B. Only the vision request shape/model
changes. Gemma thinking is disabled and output is bounded to 1,400 vision tokens;
normalization stays at 1,800 tokens. No application routing is changed.

This isolates the model pipeline. It excludes upload, authentication, private
catalog matching and diary persistence, so its latency is not camera-to-diary
latency. A prediction file contains normalized results or failures and elapsed
times for every attempted case. Source hashes, prompt hash, Git revision, runner
hash, model IDs and image hashes accompany the run. Reference labels are never
sent to inference; descriptions must be empty for this image-only comparison.

The default is a dry run with no network or credentials:

```bash
node scripts/benchmark-wellness-photo.mjs \
  --reference ml/data/reviewed-photo-subset.jsonl \
  --image-root ml/data/prepared-images --preset gemma4 --limit 5
```

Inputs use the existing nutrition_photo interchange. Unreviewed records can be
used for inference diagnostics, but cannot qualify a model in photo_benchmark.
Image SHA-256 must match; symlinks/path escapes, invalid image types and files
larger than 5 MiB fail before inference. Prepare/freeze images once with the app's
prepareImage before comparing presets; use exactly the same bytes for both.

Actual execution requires an operator-verified Workers **Free** account,
`CLOUDFLARE_FREE_ONLY=true`, `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_AI_TOKEN` in the
environment. The account-plan argument is an operator attestation, not a billing
API check. Never use it to claim a Paid account cannot incur charges.

```bash
node scripts/benchmark-wellness-photo.mjs \
  --reference ml/data/reviewed-photo-subset.jsonl \
  --image-root ml/data/prepared-images --preset current --limit 5 \
  --execute --account-plan free --output ml/runs/current-subset.jsonl
```

Each invocation permits at most ten images/twenty provider calls. There are no
automatic retries or paid fallbacks. HTTP 429 stops the run after recording the
attempted failure; remaining cases are not fabricated. The comparison scorer
rejects partial coverage. Output/manifest creation is exclusive, private (0600)
and never overwrites a prior run. Use frozen subsets and the same source revision
for both presets, then combine complete shards for the existing benchmark.

## Two-image live diagnostic, 2026-11-14

Two preselected test-split Nutrition5k dishes were used, with no private app data:
`dish_1562963325` and `dish_1562690950`. Images were processed by the actual app
prepareImage (JPEG 0.86, maximum edge 1,800; no crop). Public reference weights
were imported from the original six-total-column/seven-field-ingredient CSV
format; the importer previously incorrectly expected a count column.

The operator confirmed Workers Free. Eight real Cloudflare model calls were made
through the connected account, in order current/candidate for the first dish and
candidate/current for the second. The same normalizer/prompt/schema were used.
Timing includes the two REST calls from the connector, excluding Supabase/catalog
and local preprocessing. Artifacts remain in ignored `ml/runs/photo-model-pilot-v1`.

| Dish | Vision model | Vision time | Two model calls | Reference total | Predicted total | Absolute total-mass error |
| --- | --- | --- | --- | --- | --- | --- |
| 1562963325 | Current | 14.177 s | 26.594 s | 379 g | 200 g | 179 g |
| 1562963325 | Gemma 4 | 2.219 s | 11.640 s | 379 g | 325 g | 54 g |
| 1562690950 | Current | 7.523 s | 19.994 s | 202 g | 220 g | 18 g |
| 1562690950 | Gemma 4 | 1.906 s | 15.192 s | 202 g | 162.5 g | 39.5 g |

Gemma recognized the first dish's pizza, which the current pipeline omitted, but
still missed pork and overestimated rice. On the fruit/broccoli dish, its vision
stage correctly said blueberries while the unchanged normalizer translated that
to cranberries (חמוציות). The current pipeline also invented asparagus. A close
total weight therefore does not establish correct ingredient identification.

The candidate was faster on both cases, but mass error regressed on the second.
These two diagnostics are unreviewed benchmark records, not a representative
accuracy result, p95 estimate, independent model training or promotion approval.
The production model remains unchanged. Next: a reviewed representative corpus,
ingredient-level matching and complete failure/latency coverage, using the
qualification rules in [meal-photo-benchmark.md](meal-photo-benchmark.md).

Sources: [Nutrition5k](https://github.com/google-research-datasets/Nutrition5k)
(Thames et al., Google Research, CVPR 2021, CC BY 4.0),
[Gemma 4](https://developers.cloudflare.com/workers-ai/models/gemma-4-26b-a4b-it/),
[current vision model](https://developers.cloudflare.com/workers-ai/models/llama-3.2-11b-vision-instruct/),
[Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/).

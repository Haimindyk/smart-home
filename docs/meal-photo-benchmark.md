# Meal photo accuracy: implementation and evaluation

## Product weights available now

Tap an ingredient in a saved meal to edit its amount. For a known product, expand
“Weight range or save product”, enter the lower/upper weight for **one unit**,
enable saving, and give it a specific product name. For example, a particular
tortilla can be 50–60 g, rather than declaring every tortilla to be 55 g.

On a later meal, tap the ingredient, select that saved product and enter the
number of units. Saved foods in the food picker also default to one unit. The
midpoint is used for totals; the full range remains visible under the estimate.
The user explicitly chooses the product: a photograph of generic bread cannot
establish the brand, package weight, or number of units eaten. Other ingredients
are not scaled to force a target meal weight.

The food library lets the owner edit/remove the unit weight. Already logged meals
retain their food snapshots. g and ml stay separate. A user-confirmed weight does
not change an AI nutrient estimate into verified label/database information.
No model call, additional quota, or training contribution is needed for these
edits. Existing owner-scoped personal_foods storage, offline queue and conflict
handling are reused; there is no new table or deployment secret.

## Hosted-pipeline benchmark

The existing `wellness.evaluate` qualifies owned adapters and remains unchanged.
The new `wellness.photo_benchmark` compares complete photo pipelines offline,
including hosted models. It does not train, change runtime routing, call providers,
accept licenses, spend API budget, or promote a model.

Keep inputs, results and reports in ignored `ml/data/` or `ml/runs/`. Reference
JSONL uses the existing reviewed `nutrition_photo` interchange documented in
[ml/README.md](../ml/README.md). Every reference must have real weighed ingredient
quantities in g, an image SHA, current consent/license provenance, independent
source meal, and `reviewed: true`. User corrections, competitor guesses, and
synthetic examples are not weighed ground truth. All views of a plate must stay
together across train/validation/test; use the existing grouped preparation
pipeline and frozen test set. Public Nutrition5k labels/images can be imported
with the existing importer, attribution and manual review. Its cafeteria domain
does not replace an Israeli-food test set.

Each actual inference produces one prediction row, **including failures**:

```json
{"id":"example-id","configId":"git-sha:vision-model:normalizer-model:prompt-sha","elapsedMs":21000,"prediction":{"items":[{"name":"grilled chicken","basis":"g","quantity":110,"quantityLow":80,"quantityHigh":150,"per100":{"kcal":165,"protein":31,"carbs":0,"fat":3.6}}]}}
```

The numbers above illustrate the file format, not results from a real model.
For a timeout use `error: "analysis_failed"` instead of `prediction`; still record
elapsedMs. Predictions use the normalized production response (not raw model
text), before the user edits it. Record the exact model IDs, prompt/config hash
and Git revision in configId or an accompanying private manifest. Never expose
reference labels to inference. Compare candidates on exactly the same inputs.

Names match by case/whitespace normalization only. For Hebrew/English comparison,
provide a reviewed aliases JSON object such as `{"חזה עוף צלוי":"grilled chicken"}`.
Do not merge distinct preparations or sauces just to improve the score. Alias
chains, duplicate identities and unit conversions are rejected.

```bash
PYTHONPATH=ml python -m wellness.photo_benchmark \
  ml/data/photo-test/test.jsonl ml/runs/candidate.jsonl ml/runs/comparison.json \
  --baseline ml/runs/current.jsonl --aliases ml/data/photo-aliases.json
```

Reports include food precision/recall/F1, missing/invented items, per-meal absolute
gram error **including omitted and invented foods**, calorie/macro MAE, matched
ingredient signed bias, interval coverage AND width, valid-output rate and
p50/p95 end-to-end latency. Invalid outputs are scored as failed/empty estimates;
they cannot disappear from averages. Coverage gaps, duplicate IDs, mixed pipeline
configs and invalid elapsed times fail closed. Reference, prediction and alias
hashes make comparisons reproducible. Config labels/hashes document an operator's
run; they are not cryptographic proof that a provider executed it.

At least 100 independent meals are required for a candidate to be eligible for
review, with zero invalid outputs, lower gram error, no calorie-error increase
and no food precision/recall regression against baseline. This is an engineering
triage rule, not clinical validation or automatic model promotion. Inspect sauces,
wraps, cooked/raw ambiguity, small portions, local foods, latency and worst cases
separately before a model-selection PR. Wide intervals alone are not an accuracy
improvement.

## What is not claimed

The automated tests exercise benchmark arithmetic and product-weight behavior
with synthetic fixtures. They do **not** establish improved vision accuracy. A
reviewed 100-meal real corpus and actual baseline/candidate runs are still needed.
No private uploaded image is copied into this repository or used for training.
The existing CPU portion head and vision LoRA recipe remain unqualified for
production; there are no newly trained production weights in this change.

## Research informing the design

- [Nutrition5k, Google Research, CVPR 2021](https://github.com/google-research-datasets/Nutrition5k): weighed per-ingredient annotations, RGB/depth data and grouped train/test splits; CC BY 4.0.
- [Benchmarking Open-Source Vision–Language Models for Food Image Recognition and Portion Size Estimation](https://www.mdpi.com/2072-6643/18/21/3582): recognition and portion estimation require separate evaluation.
- [MacroFactor AI logging](https://help.macrofactorapp.com/en/articles/258-ai-food-logging): editable estimates and optional image context.
- [USDA FoodData Central](https://fdc.nal.usda.gov/api-guide/): independently sourced nutrient records, distinct from photo-based mass estimates.
- [Cloudflare Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/): bounded free inference, not guaranteed free model training.

# Wellness owned models

This directory implements training, not just prompts. It contains data preparation,
three LoRA training recipes, local inference, held-out evaluation, version manifests,
revocation lineage and a small CPU-trainable portion head. **No production adapter
has been trained or approved yet.** The registry is intentionally empty. The current
app continues to use the previously configured hosted models unless a reviewed owned
model release is explicitly selected.

An owned model here means our learned adapter/head weights, training data pipeline
and evaluation, on top of an explicitly licensed open-weight base. It does not mean
we trained a foundation model from scratch or own the base model's intellectual property.
Base IDs and immutable Hugging Face revisions are pinned in `recipes/*.json`.

| Task | Training target | Candidate base | Current state |
| --- | --- | --- | --- |
| Hebrew meal text | Food identities, explicit/estimated amounts and nutrition JSON | Mistral-7B-Instruct-v0.2, Apache 2.0 | Recipe and inference/evaluation code; not trained |
| Meal image | Food/portion/nutrition JSON from a retained meal image | Llama-3.2-11B-Vision-Instruct, Meta Llama 3.2 terms | Recipe; license acceptance and suitable GPU required |
| Program creation | Full Body/AB/ABC/custom structured catalog program | Separate Mistral adapter | Recipe; expert-reviewed program examples required |
| Portion calibration | Grams from fixed visual feature vectors | Our log-ridge regression head | CPU smoke training verified on synthetic numerical features only |

The portion head is **not** an image encoder or proof of food-recognition accuracy.
Its feature space must be fixed and validated before integration. The vision LoRA is
the actual image-to-food training path. Coaching adjustments currently continue on
the hosted path; owned-only mode rejects adjustments until a separately evaluated
adjustment recipe exists. The current coach recipe trains program creation only.

## Data ownership and collection

In Wellness Settings, adults can opt in separately to `wellness-training-v1`, choose
a saved meal/program, and approve that particular example. Consent alone never
collects a diary. Inference consent does not imply training consent. Submissions are
unreviewed, not automatically ground truth. Choosing "weighed" records the contributor's
claim about quantities; it does not verify nutrient values or technique.

Owner-scoped export uses the authenticated `wellness-training` endpoint. It contains
pseudonymous subject/source groups, not auth IDs, PINs, unrelated diary or full body
profiles. Free text/images can still identify people: review and exclude names,
faces, medical information and irrelevant notes before sharing/training. User-owned
snapshots can be reviewed by the model operator; they are not sent to train a
provider's base model. The app does not have an automatic training job.

CLI export, using an owner's short-lived JWT in the environment (never a service key):

```bash
PYTHONPATH=ml python -m wellness.export ml/exports/my-review-batch
# reads SUPABASE_URL and WELLNESS_OWNER_JWT, keeps files private, downloads retained
# images using the authenticated endpoint and replaces placeholders with SHA-256.
```

The browser export contains metadata only. A photo's `requires_owner_download` hash
is deliberately not trainable; use the CLI for a complete image export. At most 200
submissions per owner. All exports/datasets/logs/weights stay outside Git by default.
No sample private diary data or weights are included in this PR.

Offline curation must check each selected example and set `reviewed: true` only
when approved. Correct image/ingredient mismatches, amounts, units and nutrient
references; do not promote unchanged AI guesses as verified labels. Coach labels
need expert review. Keep a current consent/withdrawal inventory with the operator;
re-check it before preparing, training and releasing any model. Local exports cannot
be remotely erased by revoking consent in the app.

[Google Research Nutrition5k](https://github.com/google-research-datasets/Nutrition5k)
provides public weighed meal metadata and imagery under CC BY 4.0. The offline
`wellness.import_nutrition5k` importer processes only already-downloaded selected
RGB images/CSVs, preserves attribution, and emits **unreviewed** records. It does
not download the large dataset or silently approve labels. Ingredient names remain
as published: Hebrew/Israeli food examples still require additional curation.

## Reproducible preparation and training

Python 3.12 is the tested runtime. Use a private local/GPU environment. CPU and GPU
requirements are pinned and transitive hashes are recorded in the lockfiles.

```bash
python -m venv ml/.venv
ml/.venv/bin/python -m pip install --require-hashes -r ml/requirements-cpu.lock
PYTHONPATH=ml ml/.venv/bin/python -m unittest discover -s ml/tests -v
PYTHONPATH=ml ml/.venv/bin/python -m wellness.smoke /tmp/wellness-smoke-unique
```

The smoke run really fits and serializes weights and predicts held-out synthetic
features. Its report explicitly marks it non-production and does not report food
accuracy. Synthetic data cannot qualify for production evaluation/promotion.

Prepare a **reviewed, one-task** JSONL corpus:

```bash
PYTHONPATH=ml python -m wellness prepare ml/data/reviewed.jsonl ml/data/dataset-v1 \
  --split-salt 'stable-private-dataset-split-v1'
```

Subjects, source meals and duplicate inputs/image hashes are grouped before the
80/10/10 split. Different views of one meal cannot leak into test data. Empty splits
fail closed; a handful of household members may be insufficient for independent
holdout data. The manifest freezes split hashes, consent provenance and lineage.

On an available CUDA GPU, install `ml/requirements.lock` in a separate environment:

```bash
PYTHONPATH=ml python -m wellness.lora ml/recipes/nutrition_text.json \
  ml/data/dataset-v1 ml/runs/meal-text-v1 --accept-base-license
# For vision: recipe nutrition_photo.json and --image-root <private-local-root>.
# For plans: recipe coach_program.json and expert-reviewed catalog program labels.
```

The license flag requires that the operator actually reviewed the linked base
terms. No code accepts Meta terms, provisions a GPU, bills a service, uploads
training data or starts a cloud training job automatically. The trainer refuses
without CUDA, enough train/validation/test data or current approved annotations.
The test set is never passed to the trainer. Image samples use verified local file
hashes. Only completion tokens are trained, not the user's input prompt.

## Evaluate actual learned weights

```bash
PYTHONPATH=ml python -m wellness.predict ml/runs/meal-text-v1 \
  ml/data/dataset-v1/test.jsonl ml/runs/meal-text-v1/holdout-predictions.jsonl \
  --accept-base-license
PYTHONPATH=ml python -m wellness.evaluate ml/data/dataset-v1/test.jsonl \
  ml/runs/meal-text-v1/holdout-predictions.jsonl ml/runs/meal-text-v1/evaluation.json \
  --task nutrition_text --dataset-manifest ml/data/dataset-v1/dataset.json \
  --weights-sha256 <actual-adapter-sha256>
```

The local inference tool loads the actual adapter and pins its base revision. It
never includes target labels in the generation prompt. Evaluation checks the frozen
holdout and prediction IDs; wrong units, missing coverage and malformed output fail.
It reports calorie/quantity/macro error, exact food-label F1 and valid-output rate.
Coach evaluation reuses the production TypeScript program validator and requires
expert-reviewed examples. The initial automatic gates (50 distinct real holdout
meals, 100% valid outputs, <=20% calorie error, <=25% quantity/macro error, food F1
>=0.85, including at least five reviewed ambiguous examples requiring a question) are engineering release gates, **not clinical validation or an accuracy claim**.
Hebrew language, Israeli foods, misleading labels, ambiguous portions, pain and
adversarial input need the additional scenario evaluation in the product research.

Candidates save `adapter_model.safetensors`, `adapter_config.json`, processor assets
and a private `model-card.json` with base/dataset/weights hashes and example lineage.
`wellness.promote` refuses synthetic candidates, mismatched evaluations, missing
runtime proof or missing expert approval. It prepares metadata for a Git PR only;
it never uploads or activates a model. A reported metric cannot substitute for a
real inference run, reviewer inspection and a verified matching runtime probe.

## Cloudflare and release

Verified through the connected account: Workers AI is accessible; no existing fine
tunes were present, and Mistral v0.2 LoRA is available. Billing status could not be
read with this OAuth connection, so a Free-only account is **not verified**.

[Workers AI LoRA documentation](https://developers.cloudflare.com/workers-ai/features/fine-tunes/loras/)
requires external training, compatible bases, <=32 rank and <300 MB adapter weights.
Our recipes use rank 8. Compatibility of a specific trained adapter still requires
an actual inference probe; a successful local training run does not establish it.

Use a dedicated Workers Free account and existing hard-stop/no-paid-fallback policy.
Free Colab/Kaggle GPU sessions may be an option for public/synthetic data, subject
to their terms and availability, but this repository does not guarantee free GPUs.
Do not upload private health training data to a new GPU provider without an
appropriate disclosure/consent and retention agreement. Cloudflare inference and
GPU training are different resources.

Weights belong in private versioned artifact storage, **not** Git. Preserve
base licenses and Nutrition5k attribution with redistributed artifacts. Uploading
an adapter is a model deployment and must occur through an approved merge-triggered
release, with the exact weight hash referenced in Git. This PR does not upload any
adapter: none has passed training and evaluation yet. Add that artifact release
step alongside the first approved candidate; do not manually deploy a notebook's
latest checkpoint. Existing code releases still happen only after merging main.

The backend imports `wellness-owned-models.json`. It is empty until an approved
candidate is reviewed and committed. `WELLNESS_MODEL_SOURCE=owned` and the three
`WELLNESS_NUTRITION_TEXT_VERSION`, `WELLNESS_NUTRITION_PHOTO_VERSION`,
`WELLNESS_COACH_PROGRAM_VERSION` settings select exact approved versions. Missing,
synthetic, unverified or unsupported versions fail closed without silently falling
back to a hosted model. Own adapter requests reserve 1,600 estimated neurons each
within the shared 8,000/day budget; the provider's Free-plan limit remains the
no-spend boundary. Job results expose whether an owned adapter was actually used.

## Withdrawal and retirement

Revoking participation atomically deletes contributed rows and removes their image
references. Source meal photos remain if still retained by the user; orphans follow
the existing 24-hour cleanup. Deleting a nutrition/workout module removes its
contributed snapshots too. Deleting an individual diary row does not currently
withdraw the separate training snapshot: revoke participation to withdraw all.
No inference data is automatically converted into training data.

Already exported data and learned weights cannot be "unlearned" by deleting a
row. `wellness.retire` finds affected private model cards by example/subject lineage
and marks them retired. The operator must also remove/retire matching registry
entries in a Git PR, merge to stop serving them, erase withdrawn local exports,
and retrain from a permitted dataset. There are no production owned models yet.

Current verification covers CPU training and data plumbing, SQL/RLS/consent/quotas,
client and Edge type checks, browser approval flows, and production build. Full GPU
LoRA training and live adapter-quality evaluation remain unperformed because this
workspace has no CUDA GPU and no approved real training corpus.

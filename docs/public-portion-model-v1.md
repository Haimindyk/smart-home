# Public RGB total-plate-mass candidate v1

## Actual completed training

On 2026-11-11, trained a learned portion head on real public Nutrition5k images
and weighed total plate masses, using this workspace's CPU. No GPU, paid service,
private diary or user-uploaded photo was used. This is a new learned model head
on top of a frozen pretrained encoder, not a newly trained foundation model.

| Split | Images | Purpose |
| --- | ---: | --- |
| Train | 900 | Fit the learned weights |
| Validation | 150 | Select ridge regularization from 1, 10, 100, 1,000, 10,000 |
| Test | 250 | Evaluate the frozen selected candidate |

The encoder is torchvision MobileNet V3 Small, IMAGENET1K_V1; 576 pooled RGB
features feed our 577-coefficient log-ridge head (including intercept). Selected
regularization: 1,000. Only the head is trained. The model sees full-frame,
letterboxed 224×224 RGB pixels: no center cropping, depth, ingredient labels,
calories, masses, IDs or filename embeddings. The target is the sum of food on
the plate, **not plate/container weight and not individual ingredient grams**.

| Test metric | Trained candidate | Baseline: training median 172 g |
| --- | ---: | ---: |
| Mean absolute error | 54.23 g | 107.26 g |
| Median absolute error | 33.42 g | 92.00 g |
| Signed bias (prediction minus truth) | −10.07 g | −21.06 g |
| Mean absolute percentage error | 40.99% | 124.65% |
| Within ±25% of actual mass | 47.6% | 23.6% |

The relative reduction in mean absolute gram error is 49.44% **against that
constant baseline**, not against the app or another calorie-counting service.
Validation MAE was 55.82 g. Training and inference were executed, the candidate
was saved/reloaded, and a reproduced run produced byte-identical model weights
and identical test metrics. These results are not synthetic smoke-test numbers.

## Dataset provenance and exclusions

Source: [Google Research Nutrition5k](https://github.com/google-research-datasets/Nutrition5k),
Thames et al., CVPR 2021, CC BY 4.0. Public files are read from its official
Google Cloud Storage bucket. Use only the RGB images available in the bucket
and the official depth train/test ID subsets (depth pixels are never inputs).
Select a deterministic subset with seed `nutrition5k-rgb-total-mass-v1`. The
official test split stays held out; validation uses entire collection dates
from the official training split to keep adjacent same-day scans together.
The selected images have distinct SHA-256 values across all splits.

Before selecting the subset, exclude 239 metadata records whose total mass
differs from the summed ingredient mass by more than max(1 g, 1%), 50 records
with invalid ingredient structure, and 3 official split IDs without an overhead
image directory in the current bucket. Exclusion reasons and IDs are preserved
in the dataset manifest. This quality-screened subset is not the full official
benchmark; do not compare its scores directly with published full-split scores.
Screening is mechanical, not an expert review of every picture.

The public CSV actually starts ingredients at column 7 (zero-based index 6),
omitting the README's documented ingredient-count field. The importer now
supports both layouts and rejects shifted/truncated or nonfinite records.

## Reproduce

The optional image environment is separate from app dependencies and the base
CPU tests. Python 3.12 and Linux CPU wheels were used. Preserve the inherited
network proxy and CA settings. Runtime images/weights stay in ignored directories.

```bash
python -m venv ml/.venv
ml/.venv/bin/python -m pip install --require-hashes \
  --extra-index-url https://download.pytorch.org/whl/cpu \
  -r ml/requirements-image-cpu.lock
OPENBLAS_NUM_THREADS=3 OMP_NUM_THREADS=3 PYTHONPATH=ml \
  ml/.venv/bin/python -m wellness.image_portion \
  ml/data/nutrition5k-mass-v1 ml/runs/public-image-mass-v1 \
  --train 900 --validation 150 --test 250
```

The downloader fetches the selected RGB files, metadata and a frozen availability
listing, not the 181 GB archive. Public data and the encoder checkpoint are
cached. Feature extraction is deterministic, verifies image hashes, and saves a
cache bound to the dataset/encoder contract. The first completed extraction of
1,300 images took 22.83 seconds on this CPU; network/download time is additional.
Candidate output refuses overwriting an existing run directory.

Outputs: `model.json` (learned head plus encoder contract), `evaluation.json`,
`test-predictions.jsonl`, `run-provenance.json` and attribution. The dataset
manifest records exact image/metadata hashes, IDs, labels, exclusions and splits.
The evaluation additionally reports a paired meal-bootstrap interval for the
MAE reduction; it does not quantify unseen-cuisine or plate-group uncertainty.
Runtime library versions, training source hashes and feature/model hashes are
recorded with the run. Weights and caches are not committed to Git.

For local inference on an image using those actual weights:

```bash
OPENBLAS_NUM_THREADS=3 PYTHONPATH=ml ml/.venv/bin/python \
  -m wellness.image_portion_predict ml/runs/public-image-mass-v1/model.json \
  /path/to/meal.jpg --encoder-root ml/data/nutrition5k-mass-v1/encoder
```

The predictor checks the exact encoder/preprocessing contract, uses the same
full-frame preprocessing as training, and returns estimated total grams plus
`research_candidate_not_production`. It requires no nutritional labels as input.
A cold-load inference on one held-out photo matched its saved batch prediction
within 0.01 g; this is a reproducibility check, not a one-photo accuracy claim.

## Limits and release status

- Fixed cafeteria camera/plate setting; arbitrary phone photos lack the same
  scale and viewpoint. No Israeli-food, Hebrew, tortilla or mayonnaise benchmark.
- Total mass alone cannot tell how many grams are chicken, tortilla, sauce or
  lettuce, or resolve hidden ingredients. Do not distribute its total among
  ingredients by assumption or force an existing meal to match it.
- Almost half the held-out meals are within ±25%; this is insufficient to replace
  current food logging without broader independent comparison.
- The encoder remains an externally pretrained model; only our portion head has
  new learned weights. Preserve the torchvision BSD-3-Clause license and
  Nutrition5k CC BY 4.0 attribution with redistributed artifacts.
- No production model registry entry, Cloudflare upload, model-routing change or
  runtime activation is included. App behavior stays on its existing pipeline.
  Further integration requires representative component-level data and a
  side-by-side evaluation of the complete app pipeline, not this median baseline.

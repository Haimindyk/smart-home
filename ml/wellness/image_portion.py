"""CPU research candidate: frozen MobileNet image features -> learned plate mass.

Public Nutrition5k only. No ingredient labels, mass, calories, file IDs or depth
are input features. This is a total-mass candidate, not ingredient recognition,
an LLM correction factor or a production-qualified model.
"""
import argparse
import csv
import hashlib
import io
import json
import os
import platform
import time
import urllib.request
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from .data import digest
from .import_nutrition5k import parse_metadata
from .portion import fit, predict

BASE = "https://storage.googleapis.com/nutrition5k_dataset/nutrition5k_dataset/"
SEED = "nutrition5k-rgb-total-mass-v1"
ATTRIBUTION = "Nutrition5k, Thames et al., Google Research, CVPR 2021; CC BY 4.0; https://github.com/google-research-datasets/Nutrition5k"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def fetch(relative, root):
    path = root / relative
    if not path.is_file():
        path.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(BASE + relative, timeout=45) as response:
            content = response.read(5 * 1024 * 1024 + 1)
        if len(content) > 5 * 1024 * 1024:
            raise ValueError("unexpected_large_public_file")
        temporary = path.with_suffix(path.suffix + ".partial")
        temporary.write_bytes(content)
        temporary.replace(path)
    return path


def day(dish):
    return datetime.fromtimestamp(int(dish.removeprefix("dish_")), timezone.utc).strftime("%Y-%m-%d")


def available_images(root):
    path = root / "available-overhead-images.json"
    if path.exists():
        return set(json.loads(path.read_text()))
    ids, token = [], None
    while True:
        query = {"prefix": "nutrition5k_dataset/imagery/realsense_overhead/", "delimiter": "/",
                 "maxResults": 1000, "fields": "prefixes,nextPageToken"}
        if token:
            query["pageToken"] = token
        url = "https://storage.googleapis.com/storage/v1/b/nutrition5k_dataset/o?" + urllib.parse.urlencode(query)
        with urllib.request.urlopen(url, timeout=30) as response:
            data = json.load(response)
        ids.extend(p.rstrip("/").split("/")[-1] for p in data.get("prefixes", []))
        token = data.get("nextPageToken")
        if not token:
            break
        if len(ids) > 20000:
            raise ValueError("unexpected_dataset_listing_size")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(sorted(ids)))
    return set(ids)


def select_splits(train_ids, test_ids, targets, counts):
    if set(train_ids) & set(test_ids):
        raise ValueError("official_split_overlap")
    # Entire collection dates held out for validation, avoiding adjacent scans
    # of one plate leaking between fitting and hyperparameter selection.
    validation_days = {day(i) for i in train_ids if int(hashlib.sha256((SEED + day(i)).encode()).hexdigest()[:8], 16) % 5 == 0}
    pools = {
        "train": [i for i in train_ids if i in targets and day(i) not in validation_days],
        "validation": [i for i in train_ids if i in targets and day(i) in validation_days],
        "test": [i for i in test_ids if i in targets],
    }
    splits = {}
    for name, pool in pools.items():
        ordered = sorted(set(pool), key=lambda i: hashlib.sha256((SEED + i).encode()).hexdigest())
        if len(ordered) < counts[name]:
            raise ValueError("insufficient_public_split_" + name)
        splits[name] = ordered[:counts[name]]
    return splits


def prepare(root, counts):
    targets = {}
    provenance = {}
    excluded = []
    for name in ("dish_metadata_cafe1.csv", "dish_metadata_cafe2.csv"):
        relative = "metadata/" + name
        path = fetch(relative, root)
        provenance[relative] = sha(path)
        for values in csv.reader(io.StringIO(path.read_text())):
            if not values or values[0] == "dish_id":
                continue
            try:
                dish, mass, ingredients = parse_metadata(values)
            except (ValueError, IndexError) as error:
                excluded.append({"id": values[0], "reason": str(error)})
                continue
            if dish in targets:
                raise ValueError("duplicate_dish_metadata")
            # Check that the total target is consistent with the weighed parts.
            # Do not train on calorie-derived or model-generated gram labels.
            if abs(sum(float(i[2]) for i in ingredients) - mass) > max(1, mass * .01):
                excluded.append({"id": dish, "reason": "total_mass_differs_from_ingredient_sum"})
                continue
            targets[dish] = mass
    official = {}
    for name in ("train", "test"):
        relative = f"dish_ids/splits/depth_{name}_ids.txt"
        path = fetch(relative, root)
        provenance[relative] = sha(path)
        official[name] = path.read_text().split()
    available = available_images(root)
    provenance["available-overhead-images.json"] = sha(root / "available-overhead-images.json")
    for dish in set(official["train"] + official["test"]) - available:
        excluded.append({"id": dish, "reason": "overhead_image_not_in_public_bucket"})
    targets = {dish: mass for dish, mass in targets.items() if dish in available}
    splits = select_splits(official["train"], official["test"], targets, counts)
    jobs = [(name, dish) for name, ids in splits.items() for dish in ids]
    def download(job):
        name, dish = job
        path = fetch(f"imagery/realsense_overhead/{dish}/rgb.png", root)
        return {"id": dish, "split": name, "grams": targets[dish], "image_sha256": sha(path), "path": str(path.relative_to(root))}
    rows = []
    with ThreadPoolExecutor(max_workers=6) as executor:
        for row in executor.map(download, jobs):
            rows.append(row)
            if len(rows) % 50 == 0:
                print(f"downloaded {len(rows)}/{len(jobs)} public images", flush=True)
    hashes = [r["image_sha256"] for r in rows]
    if len(set(hashes)) != len(hashes):
        raise ValueError("duplicate_image_in_selected_splits")
    manifest = {"schema": 1, "seed": SEED, "counts": counts, "source": BASE,
                "attribution": ATTRIBUTION, "metadata_sha256": provenance, "excluded": excluded, "rows": rows}
    (root / "selected-dataset.json").write_text(json.dumps(manifest, indent=2))
    (root / "ATTRIBUTION.txt").write_text(ATTRIBUTION + "\nPublic weighed metadata; no private app data.\n")
    return manifest


def load_encoder(encoder_root):
    import torch
    from torchvision.models import MobileNet_V3_Small_Weights, mobilenet_v3_small
    torch.set_num_threads(min(3, os.cpu_count() or 1))
    torch.manual_seed(0)
    torch.hub.set_dir(str(encoder_root))
    weights = MobileNet_V3_Small_Weights.IMAGENET1K_V1
    model = mobilenet_v3_small(weights=weights).eval()
    model.classifier = torch.nn.Identity()
    state = encoder_root / "checkpoints/mobilenet_v3_small-047dcff4.pth"
    if not state.is_file():
        raise ValueError("unexpected_encoder_checkpoint")
    spec = {"architecture": "torchvision.mobilenet_v3_small", "weights": "IMAGENET1K_V1",
            "checkpoint_sha256": sha(state), "features": 576, "input": "full-frame-RGB-letterbox-224",
            "mean": [.485, .456, .406], "std": [.229, .224, .225],
            "torch": torch.__version__, "torchvision": __import__("torchvision").__version__}
    return model, spec


def image_tensor(path):
    from PIL import Image, ImageOps
    from torchvision.transforms.functional import to_tensor, normalize
    with Image.open(path) as image:
        image = ImageOps.pad(ImageOps.exif_transpose(image).convert("RGB"), (224, 224), method=Image.Resampling.BILINEAR, color=(124, 116, 104))
        return normalize(to_tensor(image), [.485, .456, .406], [.229, .224, .225])


def extract(root, manifest, encoder_root):
    import torch
    model, spec = load_encoder(encoder_root)
    cache = root / "features-v1.npz"
    cache_key = digest({"encoder": spec, "rows": manifest["rows"]})
    if cache.exists():
        with np.load(cache, allow_pickle=False) as stored:
            if str(stored["key"]) != cache_key:
                raise ValueError("feature_cache_mismatch")
            return stored["features"], spec
    features = []
    started = time.perf_counter()
    with torch.inference_mode():
        for start in range(0, len(manifest["rows"]), 16):
            batch = []
            for row in manifest["rows"][start:start + 16]:
                path = root / row["path"]
                if sha(path) != row["image_sha256"]:
                    raise ValueError("image_hash_mismatch")
                # Preserve the complete photo, never center-crop a plate.
                batch.append(image_tensor(path))
            features.extend(model(torch.stack(batch)).cpu().numpy())
            if start % 160 == 0:
                print(f"encoded {min(start + 16, len(manifest['rows']))}/{len(manifest['rows'])} images", flush=True)
    array = np.asarray(features, dtype=np.float32)
    if array.shape != (len(manifest["rows"]), 576) or not np.isfinite(array).all():
        raise ValueError("invalid_image_features")
    np.savez_compressed(cache, key=cache_key, features=array)
    spec["feature_extraction_seconds"] = time.perf_counter() - started
    return array, spec


def metrics(truth, guesses):
    truth, guesses = np.asarray(truth), np.asarray(guesses)
    if truth.shape != guesses.shape or not len(truth) or not np.isfinite(guesses).all():
        raise ValueError("invalid_predictions")
    errors = guesses - truth
    return {"examples": len(truth), "mae_g": float(np.mean(np.abs(errors))),
            "median_absolute_error_g": float(np.median(np.abs(errors))),
            "bias_g": float(np.mean(errors)), "mape": float(np.mean(np.abs(errors) / truth)),
            "within_25_percent": float(np.mean(np.abs(errors) / truth <= .25))}


def bootstrap_improvement(truth, guesses, baseline):
    truth, guesses = np.asarray(truth), np.asarray(guesses)
    errors = np.abs(guesses - truth)
    reference = np.abs(baseline - truth)
    indices = np.random.default_rng(7241).integers(0, len(truth), size=(2000, len(truth)))
    denominator = reference[indices].mean(axis=1)
    if np.any(denominator <= 0):
        return None
    samples = 1 - errors[indices].mean(axis=1) / denominator
    return {"method": "paired_meal_bootstrap", "replicates": 2000,
            "lower": float(np.quantile(samples, .025)), "upper": float(np.quantile(samples, .975)),
            "caveat": "conditional on these sampled cafeteria meals; not cross-cuisine or plate-group uncertainty"}


def train_candidate(root, output, manifest, features, encoder):
    if output.exists():
        raise ValueError("output_exists")
    rows = manifest["rows"]
    indices = {name: [i for i, r in enumerate(rows) if r["split"] == name] for name in ("train", "validation", "test")}
    if min(len(v) for v in indices.values()) < 50:
        raise ValueError("50_examples_per_split_required")
    train_rows = [{"task": "portion", "input": {"features": features[i].tolist()},
                   "target": {"grams": rows[i]["grams"]}, "synthetic": False} for i in indices["train"]]
    baseline = float(np.median([r["target"]["grams"] for r in train_rows]))
    def evaluate(model, split):
        ids = indices[split]
        truth = [rows[i]["grams"] for i in ids]
        guesses = [predict(model, features[i]) for i in ids]
        return metrics(truth, guesses), guesses
    # Tune on validation only; do not inspect test predictions until frozen.
    options = []
    models = []
    for ridge in (1., 10., 100., 1000., 10000.):
        model = fit(train_rows, ridge=ridge)
        score, _ = evaluate(model, "validation")
        options.append({"ridge": ridge, "validation": score})
        models.append(model)
    best = min(range(len(models)), key=lambda i: options[i]["validation"]["mae_g"])
    model = models[best]
    artifact = {"schema": 1, "task": "image_total_plate_mass", "status": "research_candidate_not_production",
                "encoder": {k: v for k, v in encoder.items() if k != "feature_extraction_seconds"},
                "head": model, "ridge": options[best]["ridge"], "attribution": ATTRIBUTION,
                "dataset_sha256": digest(manifest)}
    # Freeze the candidate before evaluating test labels.
    output.mkdir(parents=True)
    (output / "model.json").write_text(json.dumps(artifact, indent=2, allow_nan=False))
    validation, _ = evaluate(model, "validation")
    test, guesses = evaluate(model, "test")
    baseline_scores = {split: metrics([rows[i]["grams"] for i in indices[split]], [baseline] * len(indices[split])) for split in ("validation", "test")}
    improvement = 1 - test["mae_g"] / baseline_scores["test"]["mae_g"]
    report = {"schema": 1, "status": "research_candidate_not_production", "synthetic": False,
              "training": "learned log-ridge head on frozen RGB features; encoder not fine-tuned",
              "input_excludes": ["ingredient identities", "mass", "calories", "depth", "dish ID"],
              "dataset_sha256": digest(manifest), "model_sha256": sha(output / "model.json"),
              "counts": {k: len(v) for k, v in indices.items()}, "encoder": encoder,
              "hyperparameter_selection": options, "selected_ridge": artifact["ridge"],
              "baseline": {"kind": "training_median_plate_mass", "grams": baseline, **baseline_scores},
              "validation": validation, "test": test, "test_mae_improvement_fraction": improvement,
              "test_mae_improvement_95_interval": bootstrap_improvement([rows[i]["grams"] for i in indices["test"]], guesses, baseline),
              "production_qualified": False,
              "limitations": ["total plate mass only, not ingredient grams", "fixed cafeteria scanning setup",
                              "no Hebrew/Israeli-food validation", "not compared with the app vision pipeline",
                              "does not solve occlusion, sauces or physical scale in arbitrary phone photos"],
              "attribution": ATTRIBUTION}
    (output / "evaluation.json").write_text(json.dumps(report, indent=2, allow_nan=False))
    (output / "test-predictions.jsonl").write_text("".join(json.dumps({"id": rows[i]["id"], "grams": float(guess), "reference_grams": rows[i]["grams"]}) + "\n" for i, guess in zip(indices["test"], guesses)))
    (output / "ATTRIBUTION.txt").write_text(ATTRIBUTION + "\nFrozen encoder: torchvision BSD-3-Clause; preserve its LICENSE when redistributing.\n")
    provenance = {"python": platform.python_version(), "numpy": np.__version__,
                  "source_sha256": {p.name: sha(p) for p in [Path(__file__), Path(__file__).with_name("portion.py"), Path(__file__).with_name("import_nutrition5k.py")]},
                  "features_sha256": hashlib.sha256(np.asarray(features, dtype=np.float32).tobytes()).hexdigest(),
                  "model_sha256": report["model_sha256"], "dataset_sha256": report["dataset_sha256"]}
    (output / "run-provenance.json").write_text(json.dumps(provenance, indent=2))
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_root")
    parser.add_argument("output")
    parser.add_argument("--train", type=int, default=900)
    parser.add_argument("--validation", type=int, default=150)
    parser.add_argument("--test", type=int, default=250)
    args = parser.parse_args()
    root = Path(args.data_root)
    manifest_path = root / "selected-dataset.json"
    counts = {name: getattr(args, name) for name in ("train", "validation", "test")}
    if any(v < 50 or v > 3000 for v in counts.values()):
        raise ValueError("invalid_split_count")
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else prepare(root, counts)
    if manifest["counts"] != counts:
        raise ValueError("existing_dataset_count_mismatch")
    features, encoder = extract(root, manifest, root / "encoder")
    report = train_candidate(root, Path(args.output), manifest, features, encoder)
    print(json.dumps({"counts": report["counts"], "test": report["test"],
                      "baseline_test": report["baseline"]["test"],
                      "test_mae_improvement_fraction": report["test_mae_improvement_fraction"],
                      "production_qualified": False}, indent=2), flush=True)

"""Strict training interchange, consent checks and leakage-resistant grouped splits."""

import hashlib
import json
import math
from pathlib import Path

TASKS = {"nutrition_text", "nutrition_photo", "coach_program", "portion"}
POLICY = "wellness-training-v1"


def digest(value):
    return hashlib.sha256(
        json.dumps(
            value, sort_keys=True, ensure_ascii=False, separators=(",", ":")
        ).encode()
    ).hexdigest()


def finite(value, lo, hi):
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(value)
        or not lo <= value <= hi
    ):
        raise ValueError("invalid_numeric_label")
    return value


def validate(row):
    allowed = {
        "id",
        "task",
        "subject_group",
        "source_group",
        "consent_policy",
        "consent_active",
        "reviewed",
        "synthetic",
        "label_quality",
        "input",
        "target",
        "image",
    }
    if not isinstance(row, dict) or set(row) - allowed:
        raise ValueError("unknown_fields_or_personal_metadata")
    if (
        row.get("task") not in TASKS
        or row.get("consent_policy") != POLICY
        or row.get("consent_active") is not True
    ):
        raise ValueError("consent_required")
    if row.get("reviewed") is not True or not isinstance(row.get("synthetic"), bool):
        raise ValueError("review_required")
    for key in ("id", "subject_group", "source_group"):
        if not isinstance(row.get(key), str) or not 1 <= len(row[key]) <= 128:
            raise ValueError("missing_group")
    if row.get("label_quality") not in {
        "weighed",
        "verified_label",
        "expert_reviewed",
        "user_corrected",
        "synthetic",
    }:
        raise ValueError("unknown_label_quality")
    if row["synthetic"] != (row["label_quality"] == "synthetic"):
        raise ValueError("synthetic_provenance_mismatch")
    if not isinstance(row.get("input"), dict) or not isinstance(
        row.get("target"), dict
    ):
        raise ValueError("invalid_pair")
    if row["task"] == "portion":
        features = row["input"].get("features")
        if (
            set(row["input"]) != {"features"}
            or not isinstance(features, list)
            or not 1 <= len(features) <= 1024
        ):
            raise ValueError("invalid_features")
        for value in features:
            finite(value, -1e6, 1e6)
        finite(row["target"].get("grams"), 0.1, 10000)
        if not row["synthetic"] and row["label_quality"] != "weighed":
            raise ValueError("weighed_labels_required")
    elif row["task"].startswith("nutrition_"):
        if (
            set(row["input"]) - {"description", "mode"}
            or not isinstance(row["input"].get("description"), str)
            or len(row["input"]["description"]) > 2500
        ):
            raise ValueError("invalid_meal_input")
        if set(row["target"]) - {"items", "needsClarification", "question"}:
            raise ValueError("invalid_target_fields")
        items = row["target"].get("items")
        clarification = row["target"].get("needsClarification", False)
        if not isinstance(clarification, bool) or (
            clarification and not str(row["target"].get("question", "")).strip()
        ):
            raise ValueError("clarification_question_required")
        if (
            not isinstance(items, list)
            or not (0 if clarification else 1) <= len(items) <= 30
        ):
            raise ValueError("invalid_food_labels")
        for item in items:
            if (
                set(item) - {"name", "quantity", "basis", "per100", "source"}
                or not isinstance(item.get("name"), str)
                or not item["name"].strip()
            ):
                raise ValueError("invalid_food_label")
            finite(item.get("quantity"), 0.1, 10000)
            if item.get("basis") not in {"g", "ml"}:
                raise ValueError("invalid_basis")
            nutrients = item.get("per100", {})
            if set(nutrients) - {
                "kcal",
                "protein",
                "carbs",
                "fat",
                "fiber",
                "sugar",
                "saturatedFat",
                "sodium",
            }:
                raise ValueError("invalid_nutrient_fields")
            for key in ("fiber", "sugar", "saturatedFat", "sodium"):
                if nutrients.get(key) is not None:
                    finite(nutrients[key], 0, 100000)
            for key in ("kcal", "protein", "carbs", "fat"):
                finite(item.get("per100", {}).get(key), 0, 10000)
    else:
        if (
            set(row["input"]) - {"preferences", "description"}
            or not isinstance(row["target"].get("plans"), list)
            or not row["target"]["plans"]
        ):
            raise ValueError("invalid_coach_labels")
    if row["task"] == "nutrition_photo":
        image = row.get("image", {})
        if (
            set(image) != {"path", "sha256"}
            or not isinstance(image["path"], str)
            or not isinstance(image["sha256"], str)
            or len(image["sha256"]) != 64
        ):
            raise ValueError("local_verified_image_required")
        path = Path(image["path"])
        if path.is_absolute() or ".." in path.parts or "://" in image["path"]:
            raise ValueError("unsafe_image_path")
    if len(json.dumps(row, ensure_ascii=False)) > 150000:
        raise ValueError("example_too_large")
    return row


def read_jsonl(path):
    rows = []
    for line in Path(path).read_text().splitlines():
        if line.strip():
            rows.append(validate(json.loads(line)))
    if not rows:
        raise ValueError("empty_dataset")
    if len({r["id"] for r in rows}) != len(rows):
        raise ValueError("duplicate_id")
    return rows


def split_rows(rows, salt):
    """Union subjects, source meals AND exact inputs/images before assigning a split."""
    if len(salt) < 16:
        raise ValueError("split_salt_too_short")
    parent = {}

    def root(k):
        parent.setdefault(k, k)
        if parent[k] != k:
            parent[k] = root(parent[k])
        return parent[k]

    def union(a, b):
        a, b = root(a), root(b)
        parent[max(a, b)] = min(a, b)

    keys = []
    for row in rows:
        parts = ["subject:" + row["subject_group"], "source:" + row["source_group"]]
        if row["task"] != "nutrition_photo":
            parts.append("input:" + digest(row["input"]))
        if row.get("image"):
            parts.append("image:" + row["image"]["sha256"])
        for part in parts[1:]:
            union(parts[0], part)
        keys.append(parts[0])
    result = {name: [] for name in ("train", "validation", "test")}
    for row, key in zip(rows, keys):
        bucket = (
            int(hashlib.sha256((salt + root(key)).encode()).hexdigest()[:8], 16) % 100
        )
        result[
            "train" if bucket < 80 else "validation" if bucket < 90 else "test"
        ].append(row)
    return result


def prepare(path, output, salt, allow_synthetic=False):
    rows = read_jsonl(path)
    if any(r["synthetic"] for r in rows) and not allow_synthetic:
        raise ValueError("synthetic_data_not_allowed")
    splits = split_rows(rows, salt)
    if any(not values for values in splits.values()):
        raise ValueError("insufficient_independent_groups_for_holdout")
    out = Path(output)
    out.mkdir(parents=True, exist_ok=False)
    for split, values in splits.items():
        (out / (split + ".jsonl")).write_text(
            "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in values)
        )
    manifest = {
        "schema": 1,
        "dataset_sha256": digest(sorted(rows, key=lambda r: r["id"])),
        "synthetic": any(r["synthetic"] for r in rows),
        "counts": {k: len(v) for k, v in splits.items()},
        "split_sha256": {k: digest(v) for k, v in splits.items()},
        "example_ids": [r["id"] for r in rows],
        "subject_groups": sorted({r["subject_group"] for r in rows}),
        "split_salt_sha256": hashlib.sha256(salt.encode()).hexdigest(),
    }
    (out / "dataset.json").write_text(json.dumps(manifest, indent=2))
    return manifest

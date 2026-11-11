"""Offline import of selected licensed Nutrition5k RGB images and weighed labels."""

import argparse
import csv
import hashlib
import json
import math
import re
from pathlib import Path


def parse_metadata(values):
    """Public files omit num_ingrs despite the README's documented column.

    Accept both layouts, validating the entire ingredient tail rather than
    shifting the first ingredient into a count or silently truncating a row.
    """
    if len(values) < 13 or not re.fullmatch(r"dish_\d{10}", values[0]):
        raise ValueError("invalid_nutrition5k_row")
    start = 6 if values[6].startswith("ingr_") else 7
    tail = values[start:]
    if len(tail) % 7 or (start == 7 and int(values[6]) != len(tail) // 7):
        raise ValueError("invalid_nutrition5k_row")
    for i in range(0, len(tail), 7):
        if not tail[i].startswith("ingr_") or not tail[i + 1].strip():
            raise ValueError("invalid_nutrition5k_ingredient")
        if any(not math.isfinite(float(v)) or float(v) < 0 for v in tail[i + 2:i + 7]):
            raise ValueError("invalid_nutrition5k_values")
    mass = float(values[2])
    if not math.isfinite(mass) or not 0 < mass <= 10000:
        raise ValueError("invalid_nutrition5k_mass")
    return values[0], mass, [tail[i:i + 7] for i in range(0, len(tail), 7)]


def records(metadata, image_root):
    for values in csv.reader(Path(metadata).open()):
        if not values or values[0] == "dish_id":
            continue
        dish, _, parts = parse_metadata(values)
        ingredients = []
        for _, name, mass, kcal, fat, carbs, protein in parts:
            mass = float(mass)
            if mass <= 0:
                continue
            ingredients.append(
                {
                    "name": name,
                    "quantity": mass,
                    "basis": "g",
                    "source": "manual",
                    "per100": {
                        "kcal": float(kcal) * 100 / mass,
                        "fat": float(fat) * 100 / mass,
                        "carbs": float(carbs) * 100 / mass,
                        "protein": float(protein) * 100 / mass,
                    },
                }
            )
        if not ingredients:
            continue
        relative = f"{dish}/rgb.png"
        path = Path(image_root) / relative
        if not path.is_file():
            continue
        yield {
            "id": "nutrition5k:" + dish,
            "task": "nutrition_photo",
            "subject_group": "nutrition5k:" + dish,
            "source_group": "nutrition5k:" + dish,
            "consent_policy": "wellness-training-v1",
            "consent_active": True,
            "reviewed": False,
            "synthetic": False,
            "label_quality": "weighed",
            "input": {"description": "", "mode": "meal"},
            "target": {"items": ingredients},
            "image": {
                "path": relative,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            },
        }


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("metadata")
    p.add_argument("image_root")
    p.add_argument("output")
    p.add_argument("--accept-cc-by-4-attribution", action="store_true")
    a = p.parse_args()
    if not a.accept_cc_by_4_attribution:
        p.error(
            "Review Nutrition5k CC BY 4.0 and preserve attribution before importing"
        )
    out = Path(a.output)
    if out.exists():
        raise ValueError("output_exists")
    out.write_text(
        "".join(
            json.dumps(r, ensure_ascii=False) + "\n"
            for r in records(a.metadata, a.image_root)
        )
    )
    out.with_suffix(".attribution.txt").write_text(
        "Nutrition5k — Google Research, Thames et al., CVPR 2021. CC BY 4.0. https://github.com/google-research-datasets/Nutrition5k\nOriginal labels imported, records require image/annotation review before training.\n"
    )

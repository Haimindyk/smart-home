"""Offline import of selected licensed Nutrition5k RGB images and weighed labels."""

import argparse
import csv
import hashlib
import json
from pathlib import Path


def records(metadata, image_root):
    for values in csv.reader(Path(metadata).open()):
        if not values or values[0] == "dish_id":
            continue
        dish = values[0]
        count = int(values[6])
        ingredients = []
        if len(values) < 7 + count * 7:
            raise ValueError("invalid_nutrition5k_row")
        for i in range(count):
            _, name, mass, kcal, fat, carbs, protein = values[7 + i * 7 : 14 + i * 7]
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

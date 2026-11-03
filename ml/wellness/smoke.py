"""CPU-only synthetic training proof. Never qualifies as a food-recognition model."""

import argparse
import json
import math
from pathlib import Path
from .data import prepare, read_jsonl
from .portion import train, predict


def smoke(output):
    out = Path(output)
    out.mkdir(parents=True, exist_ok=False)
    rows = []
    for i in range(240):
        features = [math.sin(i * 0.7), math.cos(i * 0.3)]
        rows.append(
            {
                "id": f"synthetic-{i}",
                "task": "portion",
                "subject_group": f"synthetic-subject-{i}",
                "source_group": f"synthetic-meal-{i}",
                "consent_policy": "wellness-training-v1",
                "consent_active": True,
                "reviewed": True,
                "synthetic": True,
                "label_quality": "synthetic",
                "input": {"features": features},
                "target": {
                    "grams": math.exp(4 + 0.3 * features[0] - 0.2 * features[1])
                },
            }
        )
    path = out / "synthetic.jsonl"
    path.write_text("".join(json.dumps(r) + "\n" for r in rows))
    manifest = prepare(path, out / "dataset", "smoke-only-fixed-split-salt", True)
    model = train(out / "dataset", out / "candidate")
    heldout = read_jsonl(out / "dataset/test.jsonl")
    error = sum(
        abs(predict(model, r["input"]["features"]) - r["target"]["grams"])
        / r["target"]["grams"]
        for r in heldout
    ) / len(heldout)
    report = {
        "status": "synthetic_smoke_only_not_production",
        "trained_weights": len(model["weights"]),
        "split_counts": manifest["counts"],
        "numeric_pipeline_fit_error": error,
        "food_recognition_accuracy": None,
        "promotable": False,
    }
    (out / "smoke-report.json").write_text(json.dumps(report, indent=2))
    return report


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("output")
    a = p.parse_args()
    print(json.dumps(smoke(a.output), indent=2))

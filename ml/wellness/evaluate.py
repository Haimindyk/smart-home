"""Evaluate held-out predictions. Promotion never trusts training loss alone."""

import argparse
import json
import subprocess
from pathlib import Path
from .data import read_jsonl, digest, finite


def nutrients(items):
    return sum(i["quantity"] * i["per100"]["kcal"] / 100 for i in items)


def evaluate(rows, predictions, task):
    if len(rows) < 50 or any(r["synthetic"] for r in rows):
        raise ValueError("50_real_holdout_examples_required")
    if any(
        r["label_quality"] not in {"weighed", "verified_label", "expert_reviewed"}
        for r in rows
    ):
        raise ValueError("verified_holdout_labels_required")
    if len({r["source_group"] for r in rows}) < 50:
        raise ValueError("independent_holdout_required")
    if len({p["id"] for p in predictions}) != len(predictions):
        raise ValueError("duplicate_prediction")
    mapping = {p["id"]: p["prediction"] for p in predictions}
    if set(mapping) != {r["id"] for r in rows}:
        raise ValueError("prediction_coverage_mismatch")
    if task == "coach_program":
        if any(r["label_quality"] != "expert_reviewed" for r in rows):
            raise ValueError("expert_coach_review_required")
        run = subprocess.run(
            ["node", "scripts/check-wellness-coach.mjs"],
            input=json.dumps({"rows": rows, "predictions": predictions}),
            text=True,
            capture_output=True,
            check=True,
        )
        verdicts = json.loads(run.stdout)
        rate = sum(v["valid"] for v in verdicts) / len(rows)
        return {
            "examples": len(rows),
            "valid_rate": rate,
            "constraints_rate": rate,
            "passes": rate == 1,
        }
    ambiguous = sum(r["target"].get("needsClarification") is True for r in rows)
    errors = []
    food_scores = []
    quantities = []
    macro_errors = []
    valid = 0
    for row in rows:
        try:
            pred = mapping[row["id"]]
            if row["target"].get("needsClarification") is True:
                if (
                    pred.get("needsClarification") is not True
                    or not isinstance(pred.get("question"), str)
                    or not pred["question"].strip()
                    or pred.get("items") != []
                ):
                    raise ValueError("clarification_expected")
                valid += 1
                continue
            if task == "portion":
                value = finite(pred["grams"], 0.1, 10000)
                truth = row["target"]["grams"]
                errors.append(abs(value - truth) / truth)
            elif task.startswith("nutrition_"):
                items = pred["items"]
                truth = row["target"]["items"]
                if not isinstance(items, list) or len(items) > 30:
                    raise ValueError()
                for item in items:
                    finite(item["quantity"], 0.1, 10000)
                    if item["basis"] not in ("g", "ml"):
                        raise ValueError()
                    for key in ("kcal", "protein", "carbs", "fat"):
                        finite(item["per100"][key], 0, 10000)
                expected = {i["name"] for i in truth}
                actual = {i["name"] for i in items}
                food_scores.append(
                    2 * len(expected & actual) / max(1, len(expected) + len(actual))
                )
                for reference in truth:
                    match = next(
                        (i for i in items if i["name"] == reference["name"]), None
                    )
                    if match:
                        if match["basis"] != reference["basis"]:
                            raise ValueError("unit_mismatch")
                        quantities.append(
                            abs(match["quantity"] - reference["quantity"])
                            / reference["quantity"]
                        )
                for macro in ("protein", "carbs", "fat"):
                    expected_macro = sum(
                        i["quantity"] * i["per100"][macro] / 100 for i in truth
                    )
                    actual_macro = sum(
                        i["quantity"] * i["per100"][macro] / 100 for i in items
                    )
                    macro_errors.append(
                        abs(actual_macro - expected_macro) / max(5, expected_macro)
                    )
                target = nutrients(truth)
                errors.append(abs(nutrients(items) - target) / max(1, target))
            else:
                raise ValueError(
                    "coach_uses_shared_runtime_validator_and_expert_review"
                )
            valid += 1
        except (KeyError, TypeError, ValueError, ZeroDivisionError):
            errors.append(1.0)
    metrics = {
        "examples": len(rows),
        "valid_rate": valid / len(rows),
        "mape": sum(errors) / max(1, len(errors)),
        "food_f1": sum(food_scores) / len(rows) if food_scores else None,
    }
    metrics["ambiguous_examples"] = ambiguous
    metrics["quantity_mape"] = sum(quantities) / len(quantities) if quantities else None
    metrics["macro_mape"] = (
        sum(macro_errors) / len(macro_errors) if macro_errors else None
    )
    metrics["passes"] = (
        metrics["valid_rate"] == 1
        and metrics["mape"] <= 0.20
        and (
            task == "portion"
            or (
                ambiguous >= 5
                and metrics["food_f1"] >= 0.85
                and metrics["quantity_mape"] is not None
                and metrics["quantity_mape"] <= 0.25
                and metrics["macro_mape"] <= 0.25
            )
        )
    )
    return metrics


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("holdout")
    p.add_argument("predictions")
    p.add_argument("output")
    p.add_argument("--task", required=True)
    p.add_argument("--dataset-manifest", required=True)
    p.add_argument("--weights-sha256", required=True)
    a = p.parse_args()
    rows = read_jsonl(a.holdout)
    preds = [
        json.loads(s) for s in Path(a.predictions).read_text().splitlines() if s.strip()
    ]
    manifest = json.loads(Path(a.dataset_manifest).read_text())
    if manifest["split_sha256"]["test"] != digest(rows):
        raise ValueError("not_the_frozen_test_set")
    provenance = json.loads(
        Path(a.predictions).with_suffix(".provenance.json").read_text()
    )
    if (
        provenance.get("weights_sha256") != a.weights_sha256
        or provenance.get("holdout_sha256") != digest(rows)
        or provenance.get("predictions_sha256") != digest(preds)
    ):
        raise ValueError("inference_provenance_mismatch")
    report = {
        "dataset_sha256": manifest["dataset_sha256"],
        "weights_sha256": a.weights_sha256,
        "schema": 1,
        "task": a.task,
        "holdout_sha256": digest(rows),
        "predictions_sha256": digest(preds),
        "metrics": evaluate(rows, preds, a.task),
    }
    Path(a.output).write_text(json.dumps(report, indent=2))
    print(json.dumps(report["metrics"]))

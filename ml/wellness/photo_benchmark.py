"""Offline comparison of real photo estimates against reviewed, weighed meals.

This evaluates the hosted pipeline too; it does not train or promote a model.
Prediction rows: {id, configId, elapsedMs, prediction:{items:[...]}} or
{id, configId, elapsedMs, error:"analysis_failed"}. Never drop failed requests.
"""
import argparse
import json
import statistics
from pathlib import Path
from .data import digest, finite, read_jsonl


def identity(name, aliases):
    if not isinstance(name, str) or not name.strip():
        raise ValueError("invalid_food_name")
    key = " ".join(name.casefold().split())
    return aliases.get(key, key)


def foods(items, aliases):
    if not isinstance(items, list) or len(items) > 100:
        raise ValueError("invalid_items")
    result = {}
    for item in items:
        key = identity(item["name"], aliases)
        if item["basis"] != "g":
            # A volume is not a mass. Do not silently compare ml with grams.
            raise ValueError("weighed_gram_basis_required")
        if key in result:
            raise ValueError("duplicate_food_identity")
        finite(item["quantity"], 0.1, 10000)
        for nutrient in ("kcal", "protein", "carbs", "fat"):
            finite(item["per100"][nutrient], 0, 10000)
        lo, hi = item.get("quantityLow"), item.get("quantityHigh")
        if lo is not None or hi is not None:
            finite(lo, 0.1, 10000)
            finite(hi, 0.1, 10000)
            if not lo <= item["quantity"] <= hi:
                raise ValueError("invalid_interval")
        result[key] = item
    return result


def totals(items, nutrient):
    return sum(i["quantity"] * i["per100"][nutrient] / 100 for i in items.values())


def percentile(values, fraction):
    if not values:
        return None
    ordered = sorted(values)
    return ordered[round((len(ordered) - 1) * fraction)]


def benchmark(rows, predictions, aliases=None):
    aliases = aliases or {}
    if not rows or len({r["id"] for r in rows}) != len(rows):
        raise ValueError("unique_reference_ids_required")
    if any(r["task"] != "nutrition_photo" or r["label_quality"] != "weighed"
           or r["synthetic"] or not r["reviewed"] or not r["consent_active"] for r in rows):
        raise ValueError("reviewed_real_weighed_photos_required")
    # Different views of the same plate must not inflate the sample size.
    if len({r["source_group"] for r in rows}) != len(rows) or len({r["image"]["sha256"] for r in rows}) != len(rows):
        raise ValueError("independent_meals_required")
    if len({p["id"] for p in predictions}) != len(predictions):
        raise ValueError("duplicate_prediction_id")
    mapping = {p["id"]: p for p in predictions}
    if set(mapping) != {r["id"] for r in rows}:
        raise ValueError("coverage_mismatch_include_failed_requests")
    configs = {p.get("configId") for p in predictions}
    if len(configs) != 1 or not all(isinstance(c, str) and 1 <= len(c) <= 200 for c in configs):
        raise ValueError("one_named_pipeline_config_required")
    cases = []
    matched_errors, matched_bias, intervals, interval_widths = [], [], [], []
    for row in rows:
        expected = foods(row["target"]["items"], aliases)
        if not expected:
            raise ValueError("nonempty_weighed_meal_required")
        raw = mapping[row["id"]]
        elapsed = finite(raw.get("elapsedMs"), 0, 3600000)
        valid = False
        try:
            if "error" in raw:
                raise ValueError("reported_failure")
            actual = foods(raw["prediction"]["items"], aliases)
            valid = bool(actual)
        except (KeyError, TypeError, ValueError):
            actual = {}
        matched = expected.keys() & actual.keys()
        missing, extra = expected.keys() - actual.keys(), actual.keys() - expected.keys()
        error = sum(abs(actual[k]["quantity"] - expected[k]["quantity"]) for k in matched)
        # Include omitted and invented foods, preventing deceptively good scores
        # from a model that returns only the easiest component.
        error += sum(expected[k]["quantity"] for k in missing)
        error += sum(actual[k]["quantity"] for k in extra)
        for k in matched:
            delta = actual[k]["quantity"] - expected[k]["quantity"]
            matched_errors.append(abs(delta))
            matched_bias.append(delta)
            if actual[k].get("quantityLow") is not None:
                intervals.append(actual[k]["quantityLow"] <= expected[k]["quantity"] <= actual[k]["quantityHigh"])
                interval_widths.append(actual[k]["quantityHigh"] - actual[k]["quantityLow"])
        cases.append({
            "id": row["id"], "valid": valid, "elapsed_ms": elapsed,
            "matched": len(matched), "missing": len(missing), "invented": len(extra),
            "grams_absolute_error": error,
            "kcal_absolute_error": abs(totals(actual, "kcal") - totals(expected, "kcal")),
            "protein_absolute_error": abs(totals(actual, "protein") - totals(expected, "protein")),
            "carbs_absolute_error": abs(totals(actual, "carbs") - totals(expected, "carbs")),
            "fat_absolute_error": abs(totals(actual, "fat") - totals(expected, "fat")),
        })
    matched = sum(c["matched"] for c in cases)
    missing = sum(c["missing"] for c in cases)
    invented = sum(c["invented"] for c in cases)
    count = len(cases)
    metrics = {
        "meals": count, "valid_rate": sum(c["valid"] for c in cases) / count,
        "food_precision": matched / max(1, matched + invented),
        "food_recall": matched / max(1, matched + missing),
        "food_f1": 2 * matched / max(1, 2 * matched + missing + invented),
        "missing_items": missing, "invented_items": invented,
        "grams_mae_per_meal": statistics.mean(c["grams_absolute_error"] for c in cases),
        "matched_item_grams_mae": statistics.mean(matched_errors) if matched_errors else None,
        "matched_item_grams_bias": statistics.mean(matched_bias) if matched_bias else None,
        "interval_items": len(intervals),
        "interval_coverage": statistics.mean(intervals) if intervals else None,
        "interval_mean_width_g": statistics.mean(interval_widths) if interval_widths else None,
        "latency_p50_ms": percentile([c["elapsed_ms"] for c in cases], .5),
        "latency_p95_ms": percentile([c["elapsed_ms"] for c in cases], .95),
    }
    for nutrient in ("kcal", "protein", "carbs", "fat"):
        metrics[nutrient + "_mae_per_meal"] = statistics.mean(c[nutrient + "_absolute_error"] for c in cases)
    return {"config_id": next(iter(configs)), "metrics": metrics, "cases": cases}


def compare(rows, candidate, baseline=None, aliases=None):
    report = {
        "schema": 1, "purpose": "photo_pipeline_comparison_not_model_promotion",
        "reference_sha256": digest(rows), "aliases_sha256": digest(aliases or {}),
        "candidate_sha256": digest(candidate), "candidate": benchmark(rows, candidate, aliases),
    }
    # Engineering triage only. Public cafeteria tests alone do not qualify a
    # model for Israeli food, Hebrew names, privacy or clinical claims.
    report["enough_meals_for_review"] = len(rows) >= 100
    if baseline is not None:
        report["baseline_sha256"] = digest(baseline)
        report["baseline"] = benchmark(rows, baseline, aliases)
        a, b = report["candidate"]["metrics"], report["baseline"]["metrics"]
        report["candidate_eligible_for_review"] = (
            len(rows) >= 100 and a["valid_rate"] == 1
            and a["food_recall"] >= b["food_recall"]
            and a["food_precision"] >= b["food_precision"]
            and a["grams_mae_per_meal"] < b["grams_mae_per_meal"]
            and a["kcal_mae_per_meal"] <= b["kcal_mae_per_meal"]
        )
    return report


def load_predictions(path):
    return [json.loads(line) for line in Path(path).read_text().splitlines() if line.strip()]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("references")
    parser.add_argument("candidate")
    parser.add_argument("output")
    parser.add_argument("--baseline")
    parser.add_argument("--aliases", help="Reviewed JSON map from exact alternative names to canonical food names")
    args = parser.parse_args()
    aliases = json.loads(Path(args.aliases).read_text()) if args.aliases else {}
    if not isinstance(aliases, dict) or any(not isinstance(k, str) or not isinstance(v, str) or not k.strip() or not v.strip() for k, v in aliases.items()):
        raise ValueError("invalid_reviewed_alias_map")
    aliases = {identity(k, {}): identity(v, {}) for k, v in aliases.items()}
    if set(aliases) & set(aliases.values()):
        raise ValueError("alias_chains_not_allowed")
    report = compare(read_jsonl(args.references), load_predictions(args.candidate),
                     load_predictions(args.baseline) if args.baseline else None, aliases)
    output = Path(args.output)
    with output.open("x") as file:
        json.dump(report, file, ensure_ascii=False, indent=2, allow_nan=False)
    print(json.dumps({"candidate": report["candidate"]["metrics"],
                      "enough_meals_for_review": report["enough_meals_for_review"]}))

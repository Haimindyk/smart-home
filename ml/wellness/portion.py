"""A trainable portion head, not image recognition: grams from frozen visual features."""

import json
from pathlib import Path
import numpy as np
from .data import read_jsonl, digest


def fit(rows, ridge=1.0):
    if not rows or any(r["task"] != "portion" for r in rows):
        raise ValueError("portion_dataset_required")
    x = np.asarray([r["input"]["features"] for r in rows], dtype=float)
    y = np.log(np.asarray([r["target"]["grams"] for r in rows]))
    mean = x.mean(axis=0)
    scale = x.std(axis=0)
    scale[scale < 1e-8] = 1
    design = np.column_stack([np.ones(len(x)), (x - mean) / scale])
    penalty = np.eye(design.shape[1]) * ridge
    penalty[0, 0] = 0
    weights = np.linalg.solve(design.T @ design + penalty, design.T @ y)
    return {
        "schema": 1,
        "type": "log-ridge-portion",
        "features": x.shape[1],
        "mean": mean.tolist(),
        "scale": scale.tolist(),
        "weights": weights.tolist(),
        "training_sha256": digest(rows),
        "synthetic": any(r["synthetic"] for r in rows),
    }


def predict(model, features):
    x = np.asarray(features, dtype=float)
    if x.ndim != 1 or len(x) != model["features"] or not np.isfinite(x).all():
        raise ValueError("invalid_features")
    loggrams = np.dot(np.r_[1, (x - model["mean"]) / model["scale"]], model["weights"])
    return float(np.exp(np.clip(loggrams, np.log(0.1), np.log(10000))))


def train(dataset, output):
    rows = read_jsonl(Path(dataset) / "train.jsonl")
    model = fit(rows)
    out = Path(output)
    out.mkdir(parents=True, exist_ok=False)
    (out / "portion.json").write_text(json.dumps(model, indent=2))
    return model

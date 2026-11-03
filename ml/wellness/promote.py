"""Prepare reviewed registry metadata; no upload/deploy and no automatic activation."""

import argparse
import hashlib
import json
import re
from pathlib import Path
from .data import digest

BASES = {
    "nutrition_text": "@cf/mistral/mistral-7b-instruct-v0.2-lora",
    "coach_program": "@cf/mistral/mistral-7b-instruct-v0.2-lora",
    "nutrition_photo": "@cf/meta/llama-3.2-11b-vision-instruct",
}


def candidate_entry(directory, report, proof, version, lora):
    root = Path(directory)
    card = json.loads((root / "model-card.json").read_text())
    weights = root / "adapter_model.safetensors"
    sha = hashlib.sha256(weights.read_bytes()).hexdigest()
    if (
        card["status"] != "candidate"
        or card["synthetic"] is not False
        or sha != card["weights_sha256"]
    ):
        raise ValueError("not_a_real_verified_candidate")
    if card.get("training_code_dirty") is not False or not re.fullmatch(
        r"[a-f0-9]{40}", card.get("training_code_commit", "")
    ):
        raise ValueError("clean_committed_training_code_required")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{2,63}", version) or not re.fullmatch(
        r"[a-z0-9][a-z0-9-]{2,63}", lora
    ):
        raise ValueError("invalid_version_name")
    if (
        report.get("dataset_sha256") != card["dataset_sha256"]
        or report.get("weights_sha256") != sha
        or report.get("task") != card["task"]
    ):
        raise ValueError("evaluation_lineage_mismatch")
    if (
        report.get("metrics", {}).get("passes") is not True
        or report["metrics"].get("examples", 0) < 50
    ):
        raise ValueError("quality_gate_failed")
    if (
        proof.get("weights_sha256") != sha
        or proof.get("lora") != lora
        or proof.get("model") != BASES[card["task"]]
        or proof.get("passed") is not True
    ):
        raise ValueError("matching_cloudflare_runtime_probe_required")
    if proof.get("expert_reviewed") is not True:
        raise ValueError("expert_review_required")
    return {
        "id": version,
        "task": card["task"],
        "status": "approved",
        "synthetic": False,
        "weightsSha256": sha,
        "datasetSha256": card["dataset_sha256"],
        "evaluationSha256": digest(report),
        "runtimeVerified": True,
        "cloudflareModel": BASES[card["task"]],
        "lora": lora,
    }


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("candidate")
    p.add_argument("report")
    p.add_argument("runtime_proof")
    p.add_argument("--version", required=True)
    p.add_argument("--lora", required=True)
    p.add_argument(
        "--registry", default="supabase/functions/_shared/wellness-owned-models.json"
    )
    a = p.parse_args()
    entry = candidate_entry(
        a.candidate,
        json.loads(Path(a.report).read_text()),
        json.loads(Path(a.runtime_proof).read_text()),
        a.version,
        a.lora,
    )
    path = Path(a.registry)
    registry = json.loads(path.read_text())
    if any(m["id"] == entry["id"] for m in registry["models"]):
        raise ValueError("immutable_model_version")
    registry["models"].append(entry)
    path.write_text(json.dumps(registry, indent=2) + "\n")
    print(
        "Registry metadata prepared. Review in Git; no model was uploaded or activated."
    )

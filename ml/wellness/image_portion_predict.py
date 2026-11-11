"""Local inference from the actual trained total-plate-mass candidate."""
import argparse
import json
import time
from pathlib import Path
from .image_portion import load_encoder, image_tensor
from .portion import predict


def predict_file(model_path, image_path, encoder_root):
    import torch
    started = time.perf_counter()
    candidate = json.loads(Path(model_path).read_text())
    if candidate.get("task") != "image_total_plate_mass" or candidate.get("status") != "research_candidate_not_production":
        raise ValueError("unsupported_candidate")
    model, spec = load_encoder(Path(encoder_root))
    if candidate["encoder"] != spec or candidate["head"]["features"] != spec["features"]:
        raise ValueError("encoder_contract_mismatch")
    with torch.inference_mode():
        features = model(image_tensor(image_path).unsqueeze(0)).numpy()[0]
    return {"estimated_total_grams": predict(candidate["head"], features),
            "elapsed_ms_including_encoder_load": (time.perf_counter() - started) * 1000,
            "status": "research_candidate_not_production", "ingredient_estimates": None}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model")
    parser.add_argument("image")
    parser.add_argument("--encoder-root", required=True)
    args = parser.parse_args()
    print(json.dumps(predict_file(args.model, args.image, args.encoder_root), indent=2))

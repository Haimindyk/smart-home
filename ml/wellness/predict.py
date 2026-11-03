"""Local holdout inference from our actual adapter weights; labels are never prompted."""

import argparse
import hashlib
import json
from pathlib import Path
from .data import read_jsonl, digest
from .lora import samples


def run(directory, holdout, output, image_root=None, accept_base_license=False):
    if not accept_base_license:
        raise ValueError("review_and_accept_base_model_license_first")
    root = Path(directory)
    card = json.loads((root / "model-card.json").read_text())
    recipe = card["recipe"]
    task = card["task"]
    if card["status"] == "retired":
        raise ValueError("retired_model")
    if (
        hashlib.sha256((root / "adapter_model.safetensors").read_bytes()).hexdigest()
        != card["weights_sha256"]
    ):
        raise ValueError("weights_hash_mismatch")
    import torch

    if not torch.cuda.is_available():
        raise RuntimeError("GPU_required_no_cloud_job_started")
    from transformers import (
        AutoModelForCausalLM,
        AutoModelForImageTextToText,
        AutoProcessor,
        AutoTokenizer,
        BitsAndBytesConfig,
    )
    from peft import PeftModel

    cls = (
        AutoModelForImageTextToText
        if task == "nutrition_photo"
        else AutoModelForCausalLM
    )
    base = cls.from_pretrained(
        recipe["base_model"],
        revision=recipe["revision"],
        trust_remote_code=False,
        device_map="auto",
        torch_dtype=torch.float16,
        quantization_config=BitsAndBytesConfig(
            load_in_4bit=True, bnb_4bit_compute_dtype=torch.float16
        ),
    )
    model = PeftModel.from_pretrained(base, str(root))
    model.eval()
    processor = (
        AutoProcessor if task == "nutrition_photo" else AutoTokenizer
    ).from_pretrained(str(root), trust_remote_code=False)
    rows = read_jsonl(holdout)
    predictions = []
    for row in rows:
        sample = samples([row], task, image_root)[0]
        prompt = processor.apply_chat_template(
            sample["prompt"], tokenize=False, add_generation_prompt=True
        )
        if task == "nutrition_photo":
            from PIL import Image

            sample["images"] = [
                Image.open(path).convert("RGB") for path in sample["images"]
            ]
        inputs = (
            processor(
                text=prompt,
                images=sample["images"],
                return_tensors="pt",
                add_special_tokens=False,
            )
            if task == "nutrition_photo"
            else processor(prompt, return_tensors="pt", add_special_tokens=False)
        )
        inputs = inputs.to(model.device)
        with torch.inference_mode():
            tokens = model.generate(**inputs, max_new_tokens=2048, do_sample=False)
        tokenizer = processor.tokenizer if task == "nutrition_photo" else processor
        response = tokenizer.decode(
            tokens[0][inputs["input_ids"].shape[1] :], skip_special_tokens=True
        ).strip()
        try:
            prediction = json.loads(response)
        except json.JSONDecodeError:
            prediction = {"invalid_json": True}
        predictions.append({"id": row["id"], "prediction": prediction})
    out = Path(output)
    if out.exists():
        raise ValueError("output_exists")
    out.write_text(
        "".join(json.dumps(p, ensure_ascii=False) + "\n" for p in predictions)
    )
    out.with_suffix(".provenance.json").write_text(
        json.dumps(
            {
                "weights_sha256": card["weights_sha256"],
                "holdout_sha256": digest(rows),
                "predictions_sha256": digest(predictions),
                "base_revision": recipe["revision"],
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("candidate")
    p.add_argument("holdout")
    p.add_argument("output")
    p.add_argument("--image-root")
    p.add_argument("--accept-base-license", action="store_true")
    a = p.parse_args()
    run(a.candidate, a.holdout, a.output, a.image_root, a.accept_base_license)

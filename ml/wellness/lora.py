"""Explicit, local GPU training. Never uploads data or starts paid cloud jobs."""

import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from .data import read_jsonl, digest

SYSTEMS = {
    "nutrition_text": "Extract the described meal into JSON food items in Hebrew with quantity, basis and per100 nutrients. Preserve explicit quantities. Do not invent branded values. Return needsClarification and question. No medical advice.",
    "nutrition_photo": "Observe this meal image. Return JSON food items, estimated grams and per100 nutrients. Do not claim hidden ingredients are visible. No medical advice.",
    "coach_program": "Suggest a balanced exercise program using only curated exercise IDs and the supplied preferences. Return JSON plans with name, notes and exercises containing catalogId, sets, reps and rest. Never invent starting loads or medical prescriptions.",
}


def samples(rows, task, image_root=None):
    result = []
    for row in rows:
        if row["task"] != task:
            raise ValueError("mixed_tasks")
        target = row["target"]
        if task.startswith("nutrition_"):
            target = {
                **target,
                "needsClarification": target.get("needsClarification", False),
                "question": target.get("question", ""),
            }
        user = json.dumps(row["input"], ensure_ascii=False)
        if task == "nutrition_photo":
            path = (Path(image_root) / row["image"]["path"]).resolve()
            if not path.is_relative_to(Path(image_root).resolve()):
                raise ValueError("unsafe_image_path")
            if hashlib.sha256(path.read_bytes()).hexdigest() != row["image"]["sha256"]:
                raise ValueError("image_hash_mismatch")
            image = str(path)
            result.append(
                {
                    "images": [image],
                    "messages": [
                        {
                            "role": "user",
                            "content": [
                                {"type": "image"},
                                {"type": "text", "text": SYSTEMS[task] + "\n" + user},
                            ],
                        },
                        {
                            "role": "assistant",
                            "content": [
                                {
                                    "type": "text",
                                    "text": json.dumps(target, ensure_ascii=False),
                                }
                            ],
                        },
                    ],
                }
            )
        else:
            # Mistral v0.2 templates have no separate system role.
            result.append(
                {
                    "messages": [
                        {"role": "user", "content": SYSTEMS[task] + "\n" + user},
                        {
                            "role": "assistant",
                            "content": json.dumps(target, ensure_ascii=False),
                        },
                    ]
                }
            )
    return [
        {
            **{k: v for k, v in sample.items() if k != "messages"},
            "prompt": sample["messages"][:-1],
            "completion": sample["messages"][-1:],
        }
        for sample in result
    ]


def train(
    recipe_path,
    dataset,
    output,
    image_root=None,
    accept_base_license=False,
    allow_synthetic=False,
):
    recipe = json.loads(Path(recipe_path).read_text())
    task = recipe["task"]
    if not accept_base_license:
        raise ValueError("review_and_accept_base_model_license_first")
    manifest = json.loads((Path(dataset) / "dataset.json").read_text())
    splits = {
        key: read_jsonl(Path(dataset) / (key + ".jsonl"))
        for key in ("train", "validation", "test")
    }
    # Re-check provenance and split boundaries, not just editable manifest counts.
    for field in ("subject_group", "source_group"):
        groups = [{r[field] for r in rows} for rows in splits.values()]
        if any(groups[a] & groups[b] for a, b in [(0, 1), (0, 2), (1, 2)]):
            raise ValueError("holdout_leakage")
    for key, rows in splits.items():
        if any(r["task"] != task for r in rows):
            raise ValueError("mixed_tasks")
        if digest(rows) != manifest["split_sha256"][key]:
            raise ValueError("frozen_split_modified")
        if len(rows) < recipe["min_" + key]:
            raise ValueError("insufficient_" + key + "_examples")
        if any(r["synthetic"] for r in rows) and not allow_synthetic:
            raise ValueError("synthetic_data_not_allowed")
    if (
        digest(
            sorted([r for rows in splits.values() for r in rows], key=lambda r: r["id"])
        )
        != manifest["dataset_sha256"]
    ):
        raise ValueError("dataset_hash_mismatch")
    if task == "nutrition_photo" and not image_root:
        raise ValueError("private_local_image_root_required")
    import torch

    if not torch.cuda.is_available():
        raise RuntimeError("GPU_required_no_cloud_job_started")
    from datasets import Dataset, Image as DatasetImage, Sequence
    from transformers import (
        AutoModelForCausalLM,
        AutoModelForImageTextToText,
        AutoProcessor,
        AutoTokenizer,
        BitsAndBytesConfig,
    )
    from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training
    from trl import SFTConfig, SFTTrainer

    torch.manual_seed(recipe["seed"])
    cls = (
        AutoModelForImageTextToText
        if task == "nutrition_photo"
        else AutoModelForCausalLM
    )
    model = cls.from_pretrained(
        recipe["base_model"],
        revision=recipe["revision"],
        trust_remote_code=False,
        device_map="auto",
        torch_dtype=torch.float16,
        quantization_config=BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_compute_dtype=torch.float16,
        ),
    )
    model = prepare_model_for_kbit_training(model)
    # Restrict vision adaptation to the language transformer, not the vision encoder.
    targets = (
        r".*language_model.*\.(q_proj|v_proj)$"
        if task == "nutrition_photo"
        else recipe["target_modules"]
    )
    model = get_peft_model(
        model,
        LoraConfig(
            r=recipe["rank"],
            lora_alpha=recipe["alpha"],
            target_modules=targets,
            lora_dropout=0.05,
            bias="none",
            task_type="CAUSAL_LM",
        ),
    )
    processor = (
        AutoProcessor if task == "nutrition_photo" else AutoTokenizer
    ).from_pretrained(
        recipe["base_model"], revision=recipe["revision"], trust_remote_code=False
    )
    if task != "nutrition_photo" and processor.pad_token_id is None:
        processor.pad_token = processor.eos_token
    out = Path(output)
    if out.exists():
        raise ValueError("output_must_be_new_version")
    args = SFTConfig(
        output_dir=str(out),
        num_train_epochs=recipe["epochs"],
        learning_rate=recipe["learning_rate"],
        per_device_train_batch_size=1,
        per_device_eval_batch_size=1,
        gradient_accumulation_steps=8,
        gradient_checkpointing=True,
        fp16=True,
        max_length=None if task == "nutrition_photo" else recipe["max_length"],
        eval_strategy="epoch",
        save_strategy="epoch",
        save_total_limit=1,
        report_to="none",
        seed=recipe["seed"],
        completion_only_loss=True,
    )

    def dataset(rows):
        values = samples(rows, task, image_root)
        if task != "nutrition_photo":
            for sample in values:
                tokens = processor.apply_chat_template(
                    sample["prompt"] + sample["completion"], tokenize=True
                )
                if len(tokens) > recipe["max_length"]:
                    raise ValueError(
                        "example_exceeds_recipe_context_do_not_truncate_labels"
                    )
        ds = Dataset.from_list(values)
        return (
            ds.cast_column("images", Sequence(DatasetImage(mode="RGB")))
            if task == "nutrition_photo"
            else ds
        )

    trainer = SFTTrainer(
        model=model,
        args=args,
        processing_class=processor,
        train_dataset=dataset(splits["train"]),
        eval_dataset=dataset(splits["validation"]),
    )
    trainer.train()
    trainer.save_model(str(out))
    processor.save_pretrained(str(out))
    # Processor/tokenizer assets remain portable; Cloudflare only takes the adapter pair.
    config_path = out / "adapter_config.json"
    config = json.loads(config_path.read_text())
    config["model_type"] = (
        "llama" if task == "nutrition_photo" else recipe["model_type"]
    )
    config_path.write_text(json.dumps(config, indent=2))
    weights = out / "adapter_model.safetensors"
    if not weights.exists() or weights.stat().st_size >= 300_000_000:
        raise ValueError("adapter_missing_or_exceeds_cloudflare_limit")
    code_commit = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], text=True
    ).strip()
    code_dirty = bool(
        subprocess.check_output(["git", "status", "--porcelain"], text=True).strip()
    )
    card = {
        "training_code_commit": code_commit,
        "training_code_dirty": code_dirty,
        "schema": 1,
        "status": "candidate",
        "task": task,
        "recipe": recipe,
        "dataset_sha256": manifest["dataset_sha256"],
        "synthetic": any(r["synthetic"] for rows in splits.values() for r in rows),
        "weights_sha256": hashlib.sha256(weights.read_bytes()).hexdigest(),
        "examples": manifest["example_ids"],
        "subject_groups": manifest["subject_groups"],
        "base_license": recipe["license"],
        "metrics": None,
        "runtime_verified": False,
    }
    (out / "model-card.json").write_text(json.dumps(card, indent=2))
    return card


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("recipe")
    p.add_argument("dataset")
    p.add_argument("output")
    p.add_argument("--image-root")
    p.add_argument("--accept-base-license", action="store_true")
    p.add_argument("--allow-synthetic", action="store_true")
    a = p.parse_args()
    train(
        a.recipe,
        a.dataset,
        a.output,
        a.image_root,
        a.accept_base_license,
        a.allow_synthetic,
    )

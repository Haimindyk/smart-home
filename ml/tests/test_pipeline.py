import json
import math
import tempfile
import unittest
from pathlib import Path
from wellness.data import validate, split_rows, prepare
from wellness.portion import fit, predict
from wellness.evaluate import evaluate
from wellness.promote import candidate_entry
from wellness.retire import retire
from wellness.lora import samples, train


def row(i=0):
    return {
        "id": str(i),
        "task": "portion",
        "subject_group": "person-" + str(i),
        "source_group": "meal-" + str(i),
        "consent_policy": "wellness-training-v1",
        "consent_active": True,
        "reviewed": True,
        "synthetic": True,
        "label_quality": "synthetic",
        "input": {"features": [i / 100, math.sin(i)]},
        "target": {"grams": math.exp(4 + i / 100 * 0.3 - math.sin(i) * 0.2)},
    }


class PipelineTests(unittest.TestCase):
    def test_rejects_missing_consent_unreviewed_and_private_metadata(self):
        for patch in (
            {"consent_active": False},
            {"reviewed": False},
            {"owner_user_id": "private-id"},
        ):
            with self.assertRaises(ValueError):
                validate({**row(), **patch})

    def test_nonfinite_and_unweighed_portions_rejected(self):
        for patch in (
            {"target": {"grams": float("nan")}},
            {"synthetic": False, "label_quality": "user_corrected"},
        ):
            with self.assertRaises(ValueError):
                validate({**row(), **patch})

    def test_split_unions_subjects_source_meals_and_duplicate_inputs(self):
        a, b, c, d = [row(i) for i in range(4)]
        b["subject_group"] = a["subject_group"]
        c["source_group"] = b["source_group"]
        d["input"] = c["input"]
        splits = split_rows([a, b, c, d], "independent-heldout-salt")
        nonempty = [v for v in splits.values() if v]
        self.assertEqual(len(nonempty), 1)
        self.assertEqual(len(nonempty[0]), 4)

    def test_same_photo_groups_different_angles_without_merging_all_empty_descriptions(
        self,
    ):
        rows = []
        for i in range(80):
            r = {
                **row(i),
                "task": "nutrition_photo",
                "input": {"description": ""},
                "image": {"sha256": str(i).zfill(64)},
            }
            rows.append(r)
        splits = split_rows(rows, "independent-heldout-salt")
        self.assertTrue(all(splits.values()))

    def test_prepare_blocks_synthetic_production_and_freezes_holdout(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "input.jsonl"
            source.write_text("".join(json.dumps(row(i)) + "\n" for i in range(120)))
            with self.assertRaisesRegex(ValueError, "synthetic"):
                prepare(source, Path(folder) / "blocked", "long-heldout-split-salt")
            manifest = prepare(
                source, Path(folder) / "ready", "long-heldout-split-salt", True
            )
            self.assertTrue(manifest["synthetic"])
            self.assertEqual(sum(manifest["counts"].values()), 120)
            for key in ("train", "validation", "test"):
                self.assertIn(key, manifest["split_sha256"])

    def test_learns_serializable_weights_and_predicts_unseen_features(self):
        model = fit([row(i) for i in range(120)], ridge=0.01)
        restored = json.loads(json.dumps(model))
        truth = row(170)
        self.assertLess(
            abs(
                predict(restored, truth["input"]["features"]) - truth["target"]["grams"]
            )
            / truth["target"]["grams"],
            0.01,
        )
        with self.assertRaises(ValueError):
            predict(model, [float("nan"), 1])

    def test_synthetic_or_too_small_holdout_cannot_qualify(self):
        rows = [row(i) for i in range(100)]
        with self.assertRaises(ValueError):
            evaluate(rows, [], "portion")

    def test_real_portion_evaluation_catches_bad_predictions(self):
        rows = [
            {**row(i), "synthetic": False, "label_quality": "weighed"}
            for i in range(60)
        ]
        good = [{"id": r["id"], "prediction": r["target"]} for r in rows]
        self.assertTrue(evaluate(rows, good, "portion")["passes"])
        bad = [{"id": r["id"], "prediction": {"grams": 10000}} for r in rows]
        self.assertFalse(evaluate(rows, bad, "portion")["passes"])

    def test_trainer_requires_explicit_license_before_loading_gpu_dependencies(self):
        with self.assertRaisesRegex(ValueError, "license"):
            train("ml/recipes/nutrition_text.json", "missing", "unused")

    def test_prompt_completion_separates_labels(self):
        r = {
            **row(),
            "task": "nutrition_text",
            "input": {"description": "אכלתי ביצה"},
            "target": {"items": [{"name": "golden-label"}]},
        }
        sample = samples([r], "nutrition_text")[0]
        self.assertNotIn("golden-label", json.dumps(sample["prompt"]))
        self.assertIn("golden-label", json.dumps(sample["completion"]))

    def test_promote_rejects_synthetic_weights_even_with_claimed_metrics(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "adapter_model.safetensors").write_bytes(
                b"fixture-not-real-weights"
            )
            (root / "model-card.json").write_text(
                json.dumps(
                    {
                        "status": "candidate",
                        "synthetic": True,
                        "weights_sha256": "wrong",
                    }
                )
            )
            with self.assertRaisesRegex(ValueError, "real_verified"):
                candidate_entry(root, {}, {}, "v1", "test-adapter")

    def test_ambiguous_food_example_preserves_the_question_instead_of_forcing_a_guess(
        self,
    ):
        r = {
            **row(),
            "task": "nutrition_text",
            "input": {"description": "אכלתי משהו לא מזוהה"},
            "target": {
                "items": [],
                "needsClarification": True,
                "question": "איזה מזון זה היה?",
            },
        }
        validate(r)
        completion = samples([r], "nutrition_text")[0]["completion"][0]["content"]
        self.assertTrue(json.loads(completion)["needsClarification"])

    def test_withdrawal_marks_affected_model_retired(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "model-card.json"
            path.write_text(
                json.dumps(
                    {
                        "examples": ["example-a"],
                        "subject_groups": ["subject-a"],
                        "status": "candidate",
                    }
                )
            )
            self.assertTrue(retire(folder, example_ids=["example-a"]))
            self.assertEqual(json.loads(path.read_text())["status"], "retired")


if __name__ == "__main__":
    unittest.main()

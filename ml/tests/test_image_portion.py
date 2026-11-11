import copy
import json
import tempfile
import unittest
from pathlib import Path
import numpy as np
from wellness.import_nutrition5k import parse_metadata
from wellness.image_portion import select_splits, train_candidate, metrics, SEED, day


class ImagePortionTests(unittest.TestCase):
    def test_reads_actual_and_documented_public_csv_layouts(self):
        head = ["dish_1561662216", "100", "50", "1", "2", "3"]
        tail = ["ingr_0000000508", "food", "50", "100", "1", "2", "3"]
        self.assertEqual(parse_metadata(head + tail), parse_metadata(head + ["1"] + tail))
        for row in (head + ["2"] + tail, head + tail[:-1], head + ["bad"] + tail):
            with self.assertRaises(ValueError):
                parse_metadata(row)

    def test_rejects_unsafe_ids_nonfinite_and_negative_labels(self):
        row = ["dish_1561662216", "100", "50", "1", "2", "3", "ingr_0000000508", "food", "50", "100", "1", "2", "3"]
        for index, value in ((0, "../file"), (2, "nan"), (8, "-1"), (9, "inf")):
            malformed = row.copy()
            malformed[index] = value
            with self.assertRaises(ValueError):
                parse_metadata(malformed)

    def test_validation_dates_and_official_test_are_disjoint_and_selection_ignores_targets(self):
        train = [f"dish_{1556572657 + i * 86400}" for i in range(100)]
        test = [f"dish_{1576572657 + i * 86400}" for i in range(20)]
        targets = {key: 100 for key in train + test}
        counts = {"train": 10, "validation": 10, "test": 10}
        splits = select_splits(train, test, targets, counts)
        self.assertFalse(set(map(day, splits["train"])) & set(map(day, splits["validation"])))
        self.assertFalse(set(splits["train"] + splits["validation"]) & set(splits["test"]))
        self.assertEqual(splits, select_splits(train, test, {key: 900 for key in targets}, counts))
        with self.assertRaises(ValueError):
            select_splits(train, train, targets, counts)

    def test_test_labels_cannot_change_learned_weights_or_selected_hyperparameter(self):
        # Numerical fixture, not claimed public-image accuracy or a real corpus.
        features = np.random.default_rng(7).normal(size=(180, 3))
        rows = [{"id": str(i), "split": "train" if i < 60 else "validation" if i < 120 else "test",
                 "grams": float(np.exp(4 + features[i, 0] * .2))} for i in range(180)]
        manifest = {"rows": rows}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            a = train_candidate(root, root / "first", manifest, features, {"features": 3})
            changed = copy.deepcopy(manifest)
            for row in changed["rows"][120:]:
                row["grams"] *= 2
            b = train_candidate(root, root / "second", changed, features, {"features": 3})
            first = json.loads((root / "first/model.json").read_text())
            second = json.loads((root / "second/model.json").read_text())
            self.assertEqual(first["head"], second["head"])
            self.assertEqual(a["selected_ridge"], b["selected_ridge"])
            self.assertNotEqual(a["test"], b["test"])
            self.assertFalse(a["production_qualified"])

    def test_metric_units_and_positive_bias(self):
        result = metrics([100, 200], [150, 250])
        self.assertEqual(result["mae_g"], 50)
        self.assertEqual(result["bias_g"], 50)
        self.assertEqual(result["mape"], .375)


if __name__ == "__main__":
    unittest.main()

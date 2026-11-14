import csv
import hashlib
from pathlib import Path
import tempfile
import unittest
from wellness.import_nutrition5k import records


class Nutrition5kImportTests(unittest.TestCase):
    def sample(self, root, values):
        metadata = Path(root) / "metadata.csv"
        with metadata.open("w", newline="") as output:
            csv.writer(output).writerows([["dish_id"], values])
        image = Path(root) / "dish_123" / "rgb.png"
        image.parent.mkdir(exist_ok=True)
        image.write_bytes(b"public fixture image bytes")
        return list(records(metadata, root))

    def row(self):
        return ["dish_123", 245, 150, 6, 30, 20,
                "ingr_1", "rice", 50, 65, 1, 14, 1,
                "ingr_2", "fish", 100, 180, 5, 16, 19]

    def test_original_six_totals_and_seven_field_groups(self):
        with tempfile.TemporaryDirectory() as root:
            row = self.sample(root, self.row())[0]
            self.assertEqual([i["name"] for i in row["target"]["items"]], ["rice", "fish"])
            self.assertEqual([i["quantity"] for i in row["target"]["items"]], [50, 100])
            self.assertEqual(row["target"]["items"][0]["per100"]["kcal"], 130)
            self.assertFalse(row["reviewed"])
            self.assertEqual(row["label_quality"], "weighed")
            self.assertEqual(row["image"]["sha256"], hashlib.sha256(b"public fixture image bytes").hexdigest())

    def test_malformed_count_column_and_unsafe_ids_fail_closed(self):
        for values in [self.row()[:-1], self.row()[:6] + [2] + self.row()[6:], ["../dish_123"] + self.row()[1:]]:
            with self.subTest(values=values[:7]), tempfile.TemporaryDirectory() as root:
                with self.assertRaises(ValueError): self.sample(root, values)

    def test_nonfinite_and_negative_labels_are_not_imported(self):
        for index, value in [(8, "nan"), (9, "inf"), (10, -1)]:
            values = self.row(); values[index] = value
            with self.subTest(index=index), tempfile.TemporaryDirectory() as root:
                with self.assertRaises(ValueError): self.sample(root, values)


if __name__ == "__main__":
    unittest.main()

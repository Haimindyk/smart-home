import copy
import unittest
from wellness.photo_benchmark import benchmark, compare


def food(name="chicken", quantity=100, basis="g"):
    return {"name": name, "quantity": quantity, "basis": basis,
            "per100": {"kcal": 200, "protein": 20, "carbs": 0, "fat": 10}}


def reference(i=0):
    # Synthetic numerical test fixture only. No claimed real model evaluation.
    return {"id": str(i), "task": "nutrition_photo", "label_quality": "weighed",
            "reviewed": True, "synthetic": False, "consent_active": True,
            "source_group": "dish-" + str(i), "image": {"sha256": str(i)},
            "target": {"items": [food(), food("lettuce", 30)]}}


def prediction(i=0, items=None):
    return {"id": str(i), "configId": "test-fixture-not-real-inference", "elapsedMs": 1000,
            "prediction": {"items": items if items is not None else [food(), food("lettuce", 30)]}}


class PhotoBenchmarkTests(unittest.TestCase):
    def test_omissions_and_inventions_count_even_when_matched_weight_is_perfect(self):
        report = benchmark([reference()], [prediction(items=[food(), food("oil", 15)])])["metrics"]
        self.assertEqual(report["matched_item_grams_mae"], 0)
        self.assertEqual(report["grams_mae_per_meal"], 45)
        self.assertEqual(report["missing_items"], 1)
        self.assertEqual(report["invented_items"], 1)
        self.assertEqual(report["food_f1"], .5)

    def test_failure_is_not_dropped_from_accuracy_or_latency(self):
        failed = {"id": "0", "configId": "test", "elapsedMs": 60000, "error": "timeout"}
        m = benchmark([reference()], [failed])["metrics"]
        self.assertEqual(m["valid_rate"], 0)
        self.assertEqual(m["grams_mae_per_meal"], 130)
        self.assertEqual(m["kcal_mae_per_meal"], 260)
        self.assertEqual(m["latency_p95_ms"], 60000)

    def test_missing_duplicate_and_mixed_config_predictions_rejected(self):
        for preds in ([], [prediction(), prediction()], [prediction(), {**prediction(1), "configId": "other"}]):
            with self.assertRaises(ValueError):
                benchmark([reference()], preds)

    def test_invalid_units_duplicates_and_nonfinite_outputs_are_failures(self):
        for items in ([food(basis="ml")], [food(), food()], [food(quantity=float("nan"))], [{**food(), "quantityLow": 110, "quantityHigh": 120}]):
            self.assertEqual(benchmark([reference()], [prediction(items=items)])["metrics"]["valid_rate"], 0)

    def test_aliases_are_explicit_and_never_fuzzy(self):
        p = prediction(items=[food("עוף"), food("lettuce", 30)])
        self.assertEqual(benchmark([reference()], [p])["metrics"]["food_recall"], .5)
        self.assertEqual(benchmark([reference()], [p], {"עוף": "chicken"})["metrics"]["food_recall"], 1)

    def test_signed_bias_and_interval_width_are_reported(self):
        p = prediction(items=[{**food(quantity=150), "quantityLow": 90, "quantityHigh": 200}, food("lettuce", 30)])
        m = benchmark([reference()], [p])["metrics"]
        self.assertEqual(m["matched_item_grams_bias"], 25)
        self.assertEqual(m["interval_coverage"], 1)
        self.assertEqual(m["interval_mean_width_g"], 110)

    def test_unweighed_unreviewed_synthetic_and_repeated_meals_rejected(self):
        for patch in ({"label_quality": "user_corrected"}, {"reviewed": False}, {"synthetic": True}, {"consent_active": False}):
            with self.assertRaises(ValueError):
                benchmark([{**reference(), **patch}], [prediction()])
        duplicate = copy.deepcopy(reference(1))
        duplicate["source_group"] = reference()["source_group"]
        with self.assertRaises(ValueError):
            benchmark([reference(), duplicate], [prediction(), prediction(1)])

    def test_comparison_requires_100_meals_and_no_quality_regression(self):
        rows = [reference(i) for i in range(100)]
        baseline = [prediction(i, [food(quantity=150), food("lettuce", 30)]) for i in range(100)]
        better = [prediction(i) for i in range(100)]
        self.assertTrue(compare(rows, better, baseline)["candidate_eligible_for_review"])
        self.assertFalse(compare(rows[:1], better[:1], baseline[:1])["candidate_eligible_for_review"])
        self.assertFalse(compare(rows, baseline, better)["candidate_eligible_for_review"])
        self.assertEqual(compare(rows, better)["purpose"], "photo_pipeline_comparison_not_model_promotion")


if __name__ == "__main__":
    unittest.main()

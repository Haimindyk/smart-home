"""Find and mark candidates affected by withdrawn data; this is not unlearning."""

import argparse
import json
from pathlib import Path


def retire(root, example_ids=(), subject_groups=()):
    affected = []
    for path in Path(root).glob("**/model-card.json"):
        card = json.loads(path.read_text())
        if set(card.get("examples", [])) & set(example_ids) or set(
            card.get("subject_groups", [])
        ) & set(subject_groups):
            card["status"] = "retired"
            card["retirement_reason"] = "withdrawn_training_data"
            path.write_text(json.dumps(card, indent=2))
            affected.append(str(path))
    return affected


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("runs")
    p.add_argument("withdrawals")
    a = p.parse_args()
    withdrawals = json.loads(Path(a.withdrawals).read_text())
    print(
        json.dumps(
            retire(
                a.runs,
                withdrawals.get("example_ids", []),
                withdrawals.get("subject_groups", []),
            )
        )
    )

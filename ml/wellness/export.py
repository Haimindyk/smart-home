"""Owner-initiated export via authenticated app endpoint; no service-role key."""

import argparse
import hashlib
import json
import os
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.parse import urlparse


def export(url, token, output):
    parsed = urlparse(url)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.path not in ("", "/")
    ):
        raise ValueError("https_supabase_origin_required")
    endpoint = url.rstrip("/") + "/functions/v1/wellness-training"

    def call(body):
        with urlopen(
            Request(
                endpoint,
                json.dumps(body).encode(),
                {
                    "Authorization": "Bearer " + token,
                    "Content-Type": "application/json",
                },
            ),
            timeout=60,
        ) as response:
            return response.read()

    rows = json.loads(call({"action": "export"}))["examples"]
    out = Path(output)
    out.mkdir(parents=True, exist_ok=False, mode=0o700)
    try:
        (out / "images").mkdir(mode=0o700)
        for row in rows:
            if row.get("image"):
                image = call({"action": "image", "exampleId": row["id"]})
                if len(image) > 5242880:
                    raise ValueError("image_too_large")
                path = out / row["image"]["path"]
                if not path.resolve().is_relative_to(out.resolve()):
                    raise ValueError("unsafe_image_path")
                path.write_bytes(image)
                path.chmod(0o600)
                row["image"]["sha256"] = hashlib.sha256(image).hexdigest()
        path = out / "submitted.jsonl"
        path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
        path.chmod(0o600)
        (out / "export.json").write_text(
            json.dumps(
                {
                    "policy": "wellness-training-v1",
                    "review_required": True,
                    "count": len(rows),
                },
                indent=2,
            )
        )
    except Exception:
        # Incomplete exports must never look like a usable training corpus.
        (out / "INCOMPLETE").touch()
        raise
    return len(rows)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("output")
    p.add_argument("--url-env", default="SUPABASE_URL")
    p.add_argument("--token-env", default="WELLNESS_OWNER_JWT")
    a = p.parse_args()
    count = export(os.environ[a.url_env], os.environ[a.token_env], a.output)
    print(
        f"Exported {count} owner-approved submissions; offline review still required."
    )

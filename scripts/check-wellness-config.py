"""Read-only production configuration diagnostics; never emit secrets or digests."""
import hashlib
import json
import os
import urllib.error
import urllib.request

PROJECT = "ogoxwhebqxjligxeqnqd"


def matches(value, expected):
    return value in {expected, hashlib.sha256(expected.encode()).hexdigest(), hashlib.md5(expected.encode()).hexdigest()}


def summarize(rows):
    values = {row["name"]: row.get("value", "") for row in rows}
    report = {}
    for name in ("WELLNESS_AI_ENABLED", "CLOUDFLARE_FREE_ONLY"):
        value = values.get(name, "")
        report[name] = "true" if matches(value, "true") else "false" if matches(value, "false") else "missing" if not value else "set (masked or unrecognized)"
    for name in ("CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE_AI_TOKEN"):
        report[name] = "present" if values.get(name) else "missing"
    value = values.get("WELLNESS_MODEL_SOURCE", "")
    report["owned_model_mode"] = "enabled" if matches(value, "owned") else "default hosted" if not value else "set (masked or unrecognized)"
    return report


def main():
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "")
    if not token or os.environ.get("PROJECT_REF") != PROJECT:
        raise SystemExit("Wellness configuration diagnostic requires the scoped production project and access token")
    request = urllib.request.Request(f"https://api.supabase.com/v1/projects/{PROJECT}/secrets", headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            report = summarize(json.load(response))
    except (urllib.error.URLError, ValueError, KeyError, TypeError):
        # Do not print exception/response objects: they may contain private metadata.
        print("::warning::Wellness configuration diagnostic unavailable; no settings changed")
        return
    print("Wellness runtime configuration (read-only; no settings changed):")
    for key, value in report.items():
        print(f"{key}: {value}")


if __name__ == "__main__":
    main()

import { execFileSync } from "node:child_process";
import { expect, it } from "vitest";

it("reports configuration states without emitting secrets or opaque digests", () => {
  const report = JSON.parse(execFileSync("python3", ["-c", `
import runpy,json,hashlib
module=runpy.run_path('scripts/check-wellness-config.py')
print(json.dumps(module['summarize']([
 {'name':'WELLNESS_AI_ENABLED','value':hashlib.sha256(b'true').hexdigest()},
 {'name':'CLOUDFLARE_FREE_ONLY','value':'false'},
 {'name':'CLOUDFLARE_AI_TOKEN','value':'synthetic-secret-never-print'},
 {'name':'WELLNESS_MODEL_SOURCE','value':'opaque-value-never-print'}
])))
`], { encoding: "utf8" }));
  expect(report).toMatchObject({ WELLNESS_AI_ENABLED: "true", CLOUDFLARE_FREE_ONLY: "false", CLOUDFLARE_AI_TOKEN: "present", CLOUDFLARE_ACCOUNT_ID: "missing" });
  expect(JSON.stringify(report)).not.toMatch(/synthetic-secret|opaque-value|b5bea41/);
});

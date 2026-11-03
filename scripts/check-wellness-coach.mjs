// Reuse the production validator, rather than duplicating safety rules in Python.
import { build } from "esbuild";
let input = "";
for await (const part of process.stdin) input += part;
const { rows, predictions } = JSON.parse(input),
  mapping = new Map(predictions.map((p) => [p.id, p.prediction]));
const result = await build({
  entryPoints: ["supabase/functions/_shared/wellness-core.ts"],
  bundle: true,
  write: false,
  format: "esm",
  platform: "node",
});
const { makeProgram, parsePreferences } = await import(
  "data:text/javascript;base64," +
    Buffer.from(result.outputFiles[0].contents).toString("base64")
);
const verdicts = rows.map((row) => {
  try {
    makeProgram(
      mapping.get(row.id),
      parsePreferences(row.input.preferences),
      "2026-01-01",
    );
    return { id: row.id, valid: true };
  } catch {
    return { id: row.id, valid: false };
  }
});
process.stdout.write(JSON.stringify(verdicts));

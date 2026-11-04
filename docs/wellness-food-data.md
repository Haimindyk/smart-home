# Product labels and meal estimates

## Packaged products: no generative nutrition values

The packaged-product entry in the meal composer scans a barcode with the existing
on-device scanner, or accepts its digits. `food-lookup` queries Open Food Facts.
The UI shows the source and requires the user to check the product, basis and
values against the package before adding it to the draft. Open Food Facts is a
community database, not a manufacturer verification guarantee.

Missing required macros or an unknown/per-serving basis returns `needsLabel`.
The user can copy the printed values instead: calories, protein, carbohydrate and
fat are mandatory and start blank. An explicit zero is accepted; blank is not
zero. Optional nutrients stay null. Printed serving amounts are normalized by
arithmetic to 100 g or 100 ml, without converting between mass and volume. The form
also supports printed kJ (divide by 4.184), sodium grams (multiply by 1000 for mg)
or salt grams (multiply by 1000/2.5 for sodium mg).

Confirmed printed entries use `source=label` and
`sourceId=label:printed-confirmed:v1`. Legacy AI-labeled personal foods without
this marker are not used by the label-only lookup. Product-cache keys use `off:v2`
to avoid reusing historical inferred g/ml bases. Both AI endpoints reject label
mode before inference, image reads or quota reservations. The old maintenance
label-to-Gemini probe is retired. No OCR or AI reading of label photos is used:
barcode lookup or actual printed-value entry is required. These paths work while
`WELLNESS_AI_ENABLED=false`.

## Meal photos: uncertain identities stay uncertain

Llama Vision describes visible candidates in English, avoiding unreliable model
translations. Llama 3.3 70B normalizes the observations with a JSON schema. This is
an explicit photo-only model selection, with no automatic fallback. Qwen remains
the text/chat/program model. Photo normalization refuses owned-model mode until
the new contract is independently qualified for owned adapters.

The schema separates identity, alternatives, estimated quantity, bounds, g/ml
basis and per-100 nutrients. Known food-name translations are deterministic;
unmapped English identities stay English instead of inventing a Hebrew identity.
Alternatives force uncertainty even if the model says `likely`. Uncertain foods
are excluded and named in a fixed clarification message. Duplicate IDs/identities,
unknown units and mass/volume mismatches are rejected. The nutrition step cannot
rename an observed food or duplicate/reweigh its portion.

Mass kg/oz/lb and volume litres in text estimates use exact arithmetic. A cup,
spoon or piece is not silently treated as grams. Food-specific household gram
estimates remain explicitly described estimates; otherwise ask for a weighed
amount. No density is guessed to convert ml to g.

The photo draft warns that totals include listed items only. It exposes food
search/manual addition for omitted candidates and requires explicit confirmation
of corrections/missing ingredients before saving. Nutrients remain AI estimates
unless an exact, basis-matched food-catalog record supplies them. Photos do not
establish actual weights, hidden oil or preparation.

## Validation

- The original public mixed-meal photo that returned invalid cups/pieces/ounces
  was rechecked live. The selected photo normalizer returned g units, with
  ambiguous egg/tofu candidates separated from likely vegetables. The captured
  output is a regression fixture. Five retained food identities and exclusion of
  the two ambiguous candidates are tested. The image has no weighed ground truth,
  so this is not a portion/calorie accuracy benchmark.
- A real Open Food Facts lookup for barcode `3017620422003` returned Nutella,
  declared basis 100 g and 539 kcal/100 g. The production parser retained the
  source values and product URL. This is connectivity/parsing evidence, not proof
  that every record matches every local package.
- Unit tests cover mass/volume boundaries, ambiguity, duplication, printed serving
  arithmetic, kJ/sodium/salt conversion, missing fields, explicit zero and rejection
  of AI label mode. Mobile browser checks cover barcode lookup, missing-product
  printed entry, explicit confirmation, no AI calls and operation with AI disabled.

The full 50-example food evaluation, coaching evaluation and authenticated
browser-to-Edge-to-provider test remain required before broad AI enablement.

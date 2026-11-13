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
`sourceId=label:printed-confirmed:v1:<food-id>`. Legacy AI-labeled personal foods without
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
basis and per-100 nutrients. The normalizer now returns complete Hebrew names;
known canonical names still prevent conflicting translations. New photo results
with English-only or one-letter names are rejected. A compact, validated vector
stores portion [estimate, low, high] and eight ordered per-100 nutrients, reducing
repeated output tokens without changing models or dropping optional-null values.
References are assigned by the server. Alternatives still force uncertainty.
Automatic capture includes defensible best-guess candidates as estimates, while
the older manual-review contract excludes uncertain candidates. Duplicate identities,
malformed vectors, unknown units and mass/volume mismatches are rejected.

Mass kg/oz/lb and volume litres in text estimates use exact arithmetic. A cup,
spoon or piece is not silently treated as grams. Food-specific household gram
estimates remain explicitly described estimates; otherwise ask for a weighed
amount. No density is guessed to convert ml to g.

A new photo displays the captured image immediately, stops the live camera and
shows an indeterminate scan with real upload/analysis/save stages. Successful
analysis saves automatically; failure/empty results do not create a meal. The title
uses detected food names without another model request. Opening the meal shows
ingredient cards, estimated ranges and free-text AI correction; correcting an
automatic title updates it while preserving custom titles. Nutrients remain AI
estimates unless an exact, basis-matched catalog record supplies them. Photos do
not establish actual weights, hidden oil or preparation.

## Framing, wraps and visible condiments

Gallery preparation preserves the original aspect ratio and both image edges;
it never crops to the camera guide. Camera and captured-photo previews now use
contain inside a dedicated area clear of controls, so the display matches the
full frame that is analyzed. The fixed square guide is removed. Native capture
requests HD resolution when available and preserves its aspect ratio up to the
same 1800-pixel long-edge limit used by upload preparation.

Vision explicitly inspects exposed fillings/seams for visible spreads, retaining
uncertain condiment candidates rather than silently dropping them. Hidden mayo,
oil or flour type must not be claimed as visually observed. A narrowly scoped
recipe assumption can account for cooking oil as described below. Wrapped food is decomposed into one outer
sheet and separate fillings, not the entire wrap volume counted for each item.
Occlusion/unknown scale call for broad ranges, not forced competitor weights or a
blanket reduction. Prompt changes do not establish a calibrated weight estimate;
the reported wrap image was not available to independently inspect.

Saved-meal corrections can add a user-mentioned missing ingredient. Unmentioned,
negated and duplicate additions are rejected; unrelated foods and verified values
are preserved. New foods are marked as AI estimates, never database/label values.
Explicit nearby gram/ml amounts and units must match the output. Corrections that
only change a portion preserve that food's nutrient data and provenance. A live
synthetic correction probe exercised addition of mayonnaise; its nutrient values
remain estimates, not a verified product label or evidence of visual recognition.

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

- A four-food synthetic observation probe of the compact contract retained all
  foods, Hebrew names, units, portion ranges and unknown nutrient values. One
  normalization-stage probe took about 11 seconds versus about 18 seconds for
  the verbose contract. This is a single diagnostic comparison, not an end-to-end
  latency guarantee or accuracy benchmark. Faster Qwen probes were rejected for
  omissions/translation errors; the production photo model remains Llama 3.3.

## Cooking oil inferred from a recognized recipe

The compact photo contract `meal-candidates-v5-prepared-food-names` distinguishes visible
ingredients from a recipe assumption for any identified prepared dish or cooking
method, without a list of supported dish names. Each estimate carries a Hebrew
dish label, a cooking method, an exact quote from the observations/user input and
a short Hebrew rationale for expecting added oil. Unsupported evidence and
ambiguous preparation are rejected; raw foods and plain boiled/steamed foods do
not receive an automatic oil addition. A nearby fresh side does not invalidate a
separately identified fried or roasted component. Shakshuka and Moroccan fish are
examples, not special cases.
Vision still must not claim to see hidden oil. The normalizer can estimate oil
for the portion eaten, with a gram range, rather than assume oil for a whole pot
or use one constant quantity for all servings. Hidden mayonnaise is not inferred
by this exception. User oil-free preparation and explicit oil amounts override
recipe defaults; contradictory output is rejected.

Fat accounting is emitted before ingredient nutrients. Prefer decomposed foods
with nutrients excluding added oil (intrinsic egg/fish fat stays), plus one
server-created `שמן בישול — הערכת מתכון` row. Its generic fat energy factor is
approximately 9 kcal/g, source AI, not a verified oil product/database record.
If a complete dish/sauce already includes cooking fat, no extra oil row is added.
Contradictory flags, an existing oil row, impossible ranges and a claimed included
oil mass exceeding the corresponding declared total fat are rejected. This checks
structural/numerical consistency, not whether the model's nutrient estimates are
correct. Same-name catalog substitutions are skipped for these recipe estimates
because they could reintroduce oil that component estimates excluded.

The source assumption is visible in the oil's name and the existing estimate
disclosure. Automatic photo save still asks no questions. The exact correction
`לא היה שמן`, `ללא שמן`, `בלי שמן`, `no oil` or `without oil` removes only the
explicitly inferred AI oil row without another model call, and preserves other
items and label/manual foods. An oil-inclusive prepared dish requires an ordinary
preparation/nutrient correction; its unknown oil cannot safely be subtracted from
a nutrient record. No training data or independently trained model is involved.

Unit tests include fat-accounting contradictions, explicit user overrides,
multiple cuisines and cooking methods, ungrounded evidence, raw/steamed foods,
no-oil corrections and actual hosted normalizer responses to synthetic stir-fry
and steamed-broccoli observations. Archived v3 probes remain explicitly separate
and cannot be presented as v4 verification. These probes demonstrate contract handling, not
weighed nutrition accuracy or end-to-end photo recognition. The initial live
probe incorrectly declared low-fat tomato sauce to contain 10 g of oil; the new
numeric guard rejects that result. Reordering the recipe plan before food fields
resolved a later contradictory-flag probe. Model mistakes can still be rejected;
no single probe is a reliability guarantee.


## Prepared foods and breaded cutlets

Vision inspects breadcrumb/batter crust and visible seeds, distinguishes breaded
cutlets/strips from unbreaded browned meat and nuggets, and does not infer meat
species from crust alone. Hebrew translation uses schnitzel terminology only for
observed breaded chicken/turkey cutlets/strips or an explicitly named schnitzel.
Generic fried chicken, breaded fish/tofu and nuggets are not renamed as chicken
schnitzel. Visible sesame and explicit baking/air-frying/deep-frying qualifiers
are preserved when supplied in the food identity. A canonical generic identity
no longer overwrites compatible Hebrew preparation detail; inconsistent identity
translations still fall back to the canonical food.

Prepared-food nutrients should account for coating and absorbed frying fat once,
not substitute plain-meat nutrition or add oil/coating already included in a whole
prepared-food entry. Name normalization does not change quantity, quantity bounds
or nutrient numbers. An explicit saved-meal identity correction can update the
prepared-food estimate while preserving the logged weight unless the user gives
a new amount. Existing diary rows are not retrospectively reanalysed or renamed.

The screenshot observation prompt ignores dimmed duplicate backgrounds/interface
elements and treats a central food image as one view. It differentiates a real
visible sauce layer/spread from incidental crumbs, onion slivers or plate glare.
An owner-provided screenshot was probed on the existing hosted vision/normalizer
path, without feeding it a target name or gram amount. The final probe returned
a single schnitzel entry. A prior probe proposed an unsupported creamy condiment;
the trace-vs-sauce instruction was tightened. This is diagnostic evidence, not a
recognition/weight/nutrition accuracy benchmark. No private photo, raw response
or actual meal quantity is committed or used as training data.

# Live service validation — 2026-11-04

Decision: keep `WELLNESS_AI_ENABLED=false`. Connectivity works; the current
pipeline has not passed the product quality gate. A successful HTTP request or
schema parse is not evidence of reliable nutritional analysis.

## Observations

- The production database reports `wellness_ai_ready() = true`. All three Wellness
  functions are ACTIVE. Unauthenticated application requests must still return 401.
- Cloudflare accepted the Meta model agreement; a subsequent inference succeeded.
- Eight initial live text/chat cases used the exact deployed system prompts and
  structured request settings. Measured food quantities were retained, but the
  model invented unnecessary quantity bounds, sometimes omitted preparation/fat
  percentage from names, and produced poor Hebrew. The knee-pain answer included
  unsupported exercise adjustments despite the prompt's limits.
- After prompt corrections, six nutrition regressions retained measured amounts
  and collapsed their bounds. Explicit printed nutrients and a synthetic label
  read through vision both yielded 100 kcal and 160 mg sodium for a 40 g portion.
  This checks arithmetic and extraction, not food database accuracy.
- An intentionally vague meal description requested clarification without
  inventing ingredients. Four chat scenarios exercised missing logs, vegetarian
  follow-up context, pain and an extreme-restriction/instruction-injection request.
  Replies were structured but language/advice quality was uneven.
- A public mixed-meal photo was processed through Llama Vision then Qwen, using
  the actual two-stage API format. Vision asserted uncertain ingredients (including
  eggs); Qwen mistranslated foods and returned cups/pieces/ounces despite the g/ml
  contract. The application parser correctly rejects this result. Portion/calorie
  accuracy cannot be measured because the photo has no weighed ground truth.
- One Full Body beginner/dumbbell program was generated and validated locally
  against the real catalog, equipment, time and movement-pattern constraints. It
  did not invent starting weights. AB/ABC and the full 20-scenario coaching quality
  suite remain unqualified by live inference.
- A diagnostic comparison with Llama 3.3 70B produced valid units but still
  contained questionable identities/nutrients. Production model routing was NOT
  changed based on this single comparison.

## Corrections in this branch

- Measured quantities must retain exact bounds; food names must preserve stated
  preparation and fat percentage. Label placeholders and questions use Hebrew.
- Every meal-photo estimate requires explicit ingredient/portion/preparation
  confirmation; a model cannot mark photo identification as confirmed.
- Hebrew/English symptom keywords route to a deterministic stop-and-seek-help
  reply instead of model-generated exercise modifications. Urgent symptom keywords
  route to urgent help. This conservative keyword routing is not a diagnosis,
  comprehensive triage, or a clinically validated safety classifier.
- Captured synthetic/public responses are regression fixtures. Tests distinguish
  valid contracts from the rejected photo output; they do not rate model accuracy.

## Remaining release gates

1. Fix and repeat photo identification, Hebrew naming and unit/schema reliability.
   Run the documented 50-example food and 20-scenario coach evaluations with
   suitable ground truth, including unreadable labels and paired photos.
2. Review exercise illustrations against qualified references. This run did not
   generate or qualify illustrations for technique instruction.
3. Verify an authenticated browser → Edge Function → stored secret → Cloudflare →
   response flow using a consenting adult test account. No member credentials or
   session were available in this run; no sessions were read from the database,
   no membership was fabricated and no production diary data was used. A direct
   Cloudflare connector call does NOT validate the token stored in Supabase.
4. Confirm the intended account remains Workers Free, then enable only after
   these gates pass. Do not claim unlimited access or validated accuracy.

Public photo source (viewed for qualitative checking, not added to the repo):
https://images.unsplash.com/photo-1546069901-ba9599a7e63c

The label image was synthetic: per 100 g, 250 kcal, protein 10 g, carbohydrate
30 g, fat 10 g, sodium 400 mg; eaten portion 40 g. No personal images or diary
records were sent to a model.

## Follow-up implementation

The same PR now adds [product data and meal normalization](wellness-food-data.md).
Label values no longer come from AI, including in the legacy endpoint/probe.
Photo normalization explicitly selects Llama 3.3 70B, fixes canonical units and
known-name translations, and excludes ambiguous foods pending user correction.
A regression of the failed meal photo now passes these contract checks. This
does not complete the broad accuracy benchmark or authenticated application test;
keep the global enablement flag false until those remaining gates pass.

# How fitness products use AI to help the user

Research expanded on 2026-11-03 from official help pages. This describes observable
product behavior and published explanations; it does not reveal proprietary model
architectures or establish clinical effectiveness. A personalized algorithm is not
necessarily a generative model, and a support chatbot is not a training coach.

## Meal logging: MacroFactor

Sources: [AI Food Logging](https://help.macrofactorapp.com/en/articles/258-ai-food-logging)
and [Describe](https://help.macrofactorapp.com/en/articles/216-log-foods-with-describe).

The user enters a meal photo, optionally adds text, or describes the meal in natural
language. The result is an editable plate of food entries. Users can inspect
ingredients, change amounts, add/remove foods, then explicitly log the plate.
The important interaction is a draft with controls, rather than a chat answer
containing an unexplained calorie total. Describe's common-food matching should
not be confused with exact identification of a branded product; barcode/label
lookup serves a different need.

**Our implementation:** photo/text entry leads to the same editable meal composer.
Source, portion range and assumptions accompany each item. The user can correct
amounts and per-100 values before confirming. Exact catalog matches can replace
estimated nutrient values; two photos depict one plate. Nothing is logged from an
AI response alone. Corrected foods can be saved in the existing personal library.

**Next iteration:** a clarification should keep the current draft and highlight
only changed ingredients. Preserve explicitly entered grams, and ask one question
with high impact (e.g. cooked vs raw rice), rather than a lengthy nutrition interview.
Do not infer that a user correction trains a foundation model. Reuse a correction
only through a transparent, user-owned food/recipe record.

## Program creation and explanation: Fitbod

Sources: [workout creation](https://help.fitbod.me/hc/en-us/articles/360004429814-How-Fitbod-Creates-Your-Workout)
and [exercise selection](https://help.fitbod.me/hc/en-us/articles/43489509474455-How-does-Fitbod-choose-which-exercises-to-give-me).

Fitbod documents a fitness profile, goal-driven programming and exercise selection
using equipment, recovery, variety and user feedback. Users also directly control
which exercises are excluded or preferred. This forms a feedback loop: initial
preferences lead to a workout, performed sets and exercise feedback inform later
recommendations. The published inputs do not give us its ranking/recovery formula.
Do not infer a chat system's implementation from a marketing label.

**Our implementation:** structured preferences and a curated exercise catalog feed
the proposal. Rules check movement coverage, equipment, time and load progression.
The preview shows the rationale and proposed sets/reps/rest. Existing plans change
only after approval; version snapshots allow a guarded undo. The model sees
necessary performance/feedback, not the full health profile or unrelated diary.

**Next iteration:** show a short grounded explanation next to an individual change
(e.g. two completed sessions at the target), not a generic paragraph. Request missing
feedback explicitly. Add per-exercise preference/recovery only when data and a
reviewed rule justify it; never display an invented recovery percentage.

## Adapting to today's situation: Freeletics

Sources: [adapt a session](https://help.freeletics.com/hc/en-us/articles/360003933780-Adapt-your-Bodyweight-training-session)
and [coach feedback](https://help.freeletics.com/hc/en-us/articles/360011919479-Can-I-reset-my-Training-Coach).

Freeletics exposes task-focused options such as less time, no equipment or another
session. Availability depends on the training journey. Post-session feedback helps
adjust the next session. This makes the assistant useful in a concrete moment
without requiring an open-ended conversation.

**Our implementation:** goals/equipment/time/preferences and post-session energy,
pain and RIR already feed proposals. Missing feedback blocks unsupported progression.
The current adjustment UI explicitly edits the saved program, not just today's workout.

**Next iteration, separately scoped:** add a clearly named "today only" adaptation
that creates a session draft and leaves the reusable plan unchanged. Show today's
constraints before generation and compare the result before approval. Store session
feedback separately from long-term preferences. Pain must not become a prompt to
invent rehabilitation exercises or encourage training through an injury.

## Performance rules rather than generated guesses: Hevy

Source: [Hevy Trainer explained](https://help.hevyapp.com/hc/en-us/articles/38385724273047-Hevy-Trainer-Explained-How-It-Builds-Your-Workout-Program).

Hevy explicitly says its programs are algorithmically generated and do not rely on
AI. Users answer goal/experience/equipment/frequency/duration/focus questions, then
receive a program. Progression suggestions follow their performed workouts, with a
progress report. This is a useful example of personalization without making an LLM
the authority over every numerical decision.

**Our implementation:** the language model interprets the request and drafts a
proposal. Server rules, not generated claims, decide whether equipment, starting
load, maximum progression and optimistic versions are acceptable. Two completed
sessions with confirmed loads and positive feedback are required for an increase.
An unknown starting load remains unknown until the user records it.

## Intended user loop for Wellness

1. **Tell us what matters:** short goal/setup form, with optional muscle priorities.
2. **Ask for one useful action:** estimate a meal, create a split or review a plan.
3. **Inspect evidence and uncertainty:** editable foods, actual logged performance,
   clear rationale and missing information. One targeted question when needed.
4. **Approve:** save to the diary or apply a versioned plan change explicitly.
5. **Use it:** log sets or quantities without having to chat at every step.
6. **Give feedback:** effort, pain, preferences and user-owned corrections inform
   later requests. Show what changed; keep undo and manual editing available.

The first release implements this loop for meal drafts and saved-plan proposals.
The follow-up chat change adds private multi-turn conversation, optional diary
summaries and catalog technique references. Today's-session adaptation, validated
recovery scoring and longitudinal automatic calorie coaching remain future work.

## Fitness Buddy, the originally requested reference

[Fitness Buddy by Azumio](https://azum.io/apps/fitness-buddy/overview) describes
personalized plans, a large exercise library and expert training guides. Its
[features page](https://azum.io/apps/fitness-buddy/features) is a reference for
combining program choice, exercise instruction and workout tracking. Those pages
do not disclose a generative-AI architecture, so we do not attribute a specific
model or learning method to it. For our app, a clear exercise demonstration and
quick logging remain necessary even when an AI proposal is unavailable.


## Reachable meal correction and product quantities

The diary photo thumbnail and visible **Correct recognition** action open meal
details, not a raw image tab or the manual editor. The free-text correction field
is at the start of the sheet, before the photo, totals and ingredient list.
Typed corrections remain available while availability/consent/sync state explains
any disabled action. Errors retain the draft and use the shared translated error
messages. A photo whose values have become protected manual/label records shows
a manual-edit explanation rather than silently presenting an editable AI record.
The existing owner/version checks, correction IDs, quotas and source restrictions
still apply; this UI change does not allow AI to edit protected label values.
Private image links are owner-scoped, and an unavailable image does not block
opening corrections. Signed URLs from another owner/path are not displayed.

Both packaged-product scanning and barcode lookup inside food search now show
an amount selector **before adding**. Choose grams (or ml for a liquid-basis
record) or units, with an immediate total amount/calorie preview. Units require
an explicit package unit size or an already user-confirmed product unit weight;
a manufacturer servingSize alone is not assumed to mean one unit. Fractional
units and previously confirmed weight ranges are supported. Clearing a known
unit-size field does not silently refill or reuse it. New product lookups reset
the amount selection, and changing a printed-label mass/volume basis resets it
too. No density conversion is inferred.

Amount changes scale nutrition from source per100 values; they never regenerate
nutrients through AI. A selected unit size is retained in that food snapshot,
and the packaged-product flow can reuse the owner's prior confirmed unit weight
for the exact barcode/basis. Editing quantities does not rewrite previous meals.
The existing packaged-label confirmation still applies, and missing printed
macros are not filled by a model.

Verification uses the actual React components with synthetic owner/API data in
Hebrew/English mobile Chromium: diary thumbnail opens text correction in the
first viewport, updates the same meal, and does not open a raw-image tab; two
30 g product units persist as 60 g, printed 40 g persists as 40 g, the alternative
food-search barcode path persists its chosen grams, unknown unit sizes cannot
be added, and product logging works with AI disabled. This does not claim a live
authenticated production-device or camera recognition accuracy benchmark.

### Recovering an empty photo estimate

An empty result keeps the captured photo on screen. The owner can supply a short
description and analyze that same private upload again. The changed description
starts a new analysis ID; a connection or save retry retains that ID and the
description. An unchanged empty result cannot be submitted again blindly. A
successful recovery still adds the meal automatically exactly once. The normal
photo path has no new confirmation step. Browser verification uses synthetic
empty and connection-failure responses; it is not a live model accuracy result.

### Favorite meals

Bookmark a diary meal from its details header or Previous meals list. The Favorites
tab reuses that exact owner-scoped meal with its corrected food snapshots, including
mixed g/ml quantities, without AI. The new diary entry is separate and is not
automatically bookmarked. Removing a bookmark keeps diary history; deleting the
source entry removes its bookmark too, stated in the existing delete confirmation.
Favorite state uses the existing meal JSON payload/offline queue and version guard,
not a gram-only recipe conversion or local-only preference. Legacy rows without a
flag remain valid. A read-only live validator query accepted legacy, favorite and
unfavorite synthetic payloads; no production diary rows were changed by that check.

### Focused portion editing

Tap an ingredient's amount to open a dedicated amount sheet. The numeric field is
immediately visible, with a local calorie preview; saved-product selection and
unit-weight saving are optional disclosures. Cancel returns to the same meal.
Only the chosen ingredient changes, with no AI call or changes to other portions.
The editor retains the original meal/version snapshot while saving, so a local
store update does not remount it or discard the draft. Concurrent edits require
reopening; an exactly accepted queued save is recognized after a later cache error.

### Explicit measured training examples

Training participation and approval remain separate and optional. For a weighed
nutrition example, the contributor enters a gram weight for every ingredient;
fields start blank rather than copying model estimates. Changing the selected
record/task clears the measurement claim and inputs, and changing a description
or weight clears per-example approval. The diary itself is not modified.

The server matches weights by ingredient ID, requires complete finite positive
gram measurements and the selected source version, and rejects duplicates,
unknown/missing ingredients and ml-based foods. Ordinary corrected examples stay
available without pretending volumes are grams. A status capability gates the
new measured form so an older server cannot silently ignore explicit weights
during a rolling release. No database schema or training-consent policy changes.

These remain self-reported measurements, stored as **unreviewed** examples. Weighing
quantities does not verify AI nutrient values; original nutrient sources are
retained and independent review is still required before training/evaluation.
No model is automatically trained, promoted or claimed more accurate by this change.

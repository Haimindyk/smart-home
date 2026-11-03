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
A multi-turn assistant, today's-session adaptation, validated recovery scoring and
longitudinal calorie coaching are future work, not capabilities claimed by this PR.

## Fitness Buddy, the originally requested reference

[Fitness Buddy by Azumio](https://azum.io/apps/fitness-buddy/overview) describes
personalized plans, a large exercise library and expert training guides. Its
[features page](https://azum.io/apps/fitness-buddy/features) is a reference for
combining program choice, exercise instruction and workout tracking. Those pages
do not disclose a generative-AI architecture, so we do not attribute a specific
model or learning method to it. For our app, a clear exercise demonstration and
quick logging remain necessary even when an AI proposal is unavailable.

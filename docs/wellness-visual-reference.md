# Wellness visual reference

The user supplied mobile Cali screens and clarified that the goal is appearance
and ease of use. Use those screens for spacing, type hierarchy and interaction
patterns. Preserve the app's own data, labels and capabilities; do not invent
community/shopping counters, activity, nutrient goals or an OS status bar.

The shared language is Heebo, a white background, black primary actions, neutral
outlined choices, rounded cards/sheets and restrained nutrition accents. Active
choice pills are black with white text. Secondary explanations belong behind
disclosures rather than between the daily summary and meal diary.

## Daily view acceptance

- The calorie card and macro cards fit a phone without excessive nested padding.
- Today's meal heading and the start of the first entry are visible above the
  fixed navigation at 390 × 844; the page fits 320 px without horizontal overflow.
- The date rail centers the selected date, shows roughly a week at phone widths,
  retains the visible month/year and marks activity only from actual records.
- Empty consumption renders zero-progress rings. Over-goal amounts remain visible
  with an explicit label and warm accent instead of being clamped to zero.
- Add opens a white bottom sheet with six evenly arranged primary choices;
  manual entry remains available as a secondary action.
- Meal cards prioritize dish name, concise description and calories; meal-kind
  group headings remain accessible while taking no extra visual row.

The browser suite captures Hebrew/English empty, populated, over-goal and small
phone layouts and the add sheet. Screenshots use synthetic data at the actual
component boundary; they are not invented diary entries in production.

The overall reference goal remains broader than this daily-view increment.
Continue comparing chat, activity logging, text entry, product search, favorites,
progress/settings and camera against the supplied references on real devices.

## Conversation and workout cards

- Chat starts with one short welcome bubble, horizontal draft suggestions and a
  compact composer. Refresh, deletion, quota and navigation/help are available
  under Chat options. AI consent and errors stay visible when action is needed.
- Diary sharing stays off by default. Short visible copy retains its full
  accessible label; selecting a suggestion only fills an editable draft.
- At 390 px and 320 px, the initial send action remains above the fixed navigation
  with no horizontal page overflow. These assertions run without screenshot flags.
- Workout plan cards occupy a full row on phones and two columns above 600 px.
  Scheduling information cannot overlap the day title; start/edit remain visible.

## Meal entry sheets

Meal description, manual entry and packaged products use the shared white editor
sheet, with a centered title, a handle and one accessible close action. Close and
dismissal stay disabled while a save/analysis is pending. Description entry has a
large text area and a black pill action; secondary precision tips stay collapsed.
Product scanning continues to open directly, with camera/manual barcode and real
package values. This visual change does not alter confirmation or diary writes.

## Favorites access

The add sheet keeps saved foods as a separate destination and also provides a
direct Favorite meals action. Favorites opens the bookmarked meal list without
requiring the user to discover it inside Previous meal. Its empty state explains
bookmarking briefly and offers one action to browse recent meals. No diary write
or AI call is needed to browse either list.

## Figma design

[Editable wellness design](https://www.figma.com/design/3aF3x3dYm9D7nlfmoJKSq0)
contains eight Hebrew screen concepts (daily overview, adding food, description,
barcode, camera, correction, chat and workouts), using Heebo and reusable assets.
The board uses illustrative data, not production diary entries. The code remains
in GitHub; Figma is the visual planning/reference artifact. The user chose to continue directly in code without paid Figma. The optional
board is a visual reference; its unfinished prototype does not gate application
work. Validate actual components in the browser against the supplied references.
Do not treat the board as a tested live app or claim complete parity.

## Progress overview

Week/month selection uses the shared pill controls. Each recorded series shows
its latest value and date; a single entry has a short explanation instead of a
mostly empty trend graph. Series with at least two records retain their chart.
Detailed intake, weigh-ins and performance histories stay behind disclosures.
Workout summary cards appear only when workout tracking is enabled. Browser
checks cover sparse and multi-entry series, period selection, detailed-table
access, nutrition-only profiles and narrow mobile layouts using synthetic data.

## Food search

Food search opens directly with one search row and a barcode action. Recent/saved
choices appear only for text search, not barcode or manual entry. Barcode mode
shows barcode results and has an explicit return path. Typing in saved foods filters locally; an explicit search can also open the
shared catalog. Lists scroll with the sheet.
Manual entry shows the four core nutrients and amount first; optional nutrients
stay in a disclosure. Units and nutrient labels use the user's language. Search status and empty states explain the next action briefly.

# Product research for Wellness

Reviewed official product/help pages on 2026-11-03. These are product references,
not access to the products' private code, training data or recommendation algorithms.
We use our own interface, rules and curated exercise identities. No scraped images,
workout databases or claims to replicate a competitor's model.

| Reference | Useful behavior | Applied in this change | Later evaluation |
| --- | --- | --- | --- |
| [Fitbod: workout creation](https://help.fitbod.me/hc/en-us/articles/360004429814-How-Fitbod-Creates-Your-Workout), [exercise selection](https://help.fitbod.me/hc/en-us/articles/43489509474455-How-does-Fitbod-choose-which-exercises-to-give-me) | Adapt to goals, experience, available equipment and time; use workout history | Structured preferences, Full Body/AB/ABC/custom splits, muscle priorities, avoided exercises, rotating days, server validation of equipment and estimated duration | Per-muscle recovery and volume trends after sufficient real history. Do not claim to reproduce Fitbod's recovery algorithm. |
| [MacroFactor: coaching check-ins](https://help.macrofactorapp.com/en/articles/247-introduction-to-check-ins-and-coaching-modules), [logging consistency](https://help.macrofactorapp.com/en/articles/110-how-frequently-do-i-need-to-log-my-nutrition-for-the-expenditure-algorithm-and-weekly-coaching-updates) | Explicit check-ins; interpret missing nutrition records carefully | Editable food drafts and explicit plan approval; no inference that missing food logs mean zero intake; no automatic changes to calorie targets | Weight-trend coaching with an explicit completeness check. This release does not estimate energy expenditure from incomplete logs. |
| [Cronometer: data sources](https://support.cronometer.com/hc/en-us/articles/360018239472-Data-Sources), [confidence scores](https://support.cronometer.com/hc/en-us/articles/360042550452-Data-Confidence-Scores) | Expose provenance and completeness of food data | Exact name+basis catalog matching; distinguish USDA, label and AI estimates; preserve unknown optional nutrients as null; editable plausible portion ranges | Curated food aliases and better Hebrew household measures. Portion ranges are not statistically calibrated confidence intervals. |
| [Hevy: features](https://www.hevyapp.com/features/), [RPE/RIR](https://help.hevyapp.com/hc/en-us/articles/34490600233111-RPE-vs-RIR-What-They-Mean-and-How-to-Use-Them-in-Hevy) | Fast set logging, prior performances and useful effort feedback | Existing logging retained; add energy, pain and RIR feedback; require two completed performances with confirmed load and positive feedback before progression | Exercise-specific RIR and deload recommendations after enough confirmed history. No diagnosis or rehab prescriptions. |

## Decisions for our app

- Full Body, AB and ABC are cycle lengths, not fixed weekday names. For example,
  five ABC workouts continue A/B/C/A/B then C/A/B/C/A in the next week.
- The model proposes exercises using curated IDs. The server rejects unknown
  exercises, missing movement patterns, unavailable equipment and overlong plans.
- Unknown starting weights remain blank. Logged, explicitly confirmed weights can
  establish a baseline; increases are capped and need two completed sessions.
- Photos cannot reliably reveal oil, ingredients or exact mass. Show assumptions,
  preserve user quantities and ask a useful clarification instead of inventing certainty.
- A second photo depicts the same plate. Combine views into one observation rather
  than adding the calories twice. Never infer grams from millilitres without a density.
- A reliable existing demonstration takes precedence. Otherwise generate a clearly
  marked illustration, pending user review. A user's review is not professional
  certification. Unknown manual exercise names require a catalog choice; no invented
  exercise technique. Saving the exercise never depends on image availability.

## Evaluation before enabling the service

Use a consented or synthetic set of at least 50 varied food examples (mixed plates,
Israeli foods, cooked/raw, sauces, packages and unreadable labels), with weighed
portions or verified labels. Report ingredient recognition, portion/calorie error,
clarification frequency and Hebrew unit handling separately. Do not present a
single "accuracy" number without these conditions. Include paired views of the
same plate and zero/one user-provided quantity.

For coaching, evaluate at least 20 preference/history scenarios: limited equipment,
20-minute sessions, beginner/advanced, each split, priorities, avoided exercises,
pain, fatigue, missing feedback, explicit zero external load and stale proposals.
Verify the absence of unsupported load progression and inspect every new exercise
illustration against a qualified reference before relying on it for technique.

Local automated tests check these rules with deterministic fixtures and mocked
provider responses. Live model quality has not yet been measured; API credentials
and this evaluation are needed before enabling the service.

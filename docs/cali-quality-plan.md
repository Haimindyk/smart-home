# Wellness quality target and working acceptance checks

Reference reviewed 2026-11-14: [Cali's public product page](https://caliaiapp.com/en)
and [its Israeli App Store listing](https://apps.apple.com/il/app/cali-ai-nutrition-tracker/id6757074222).
These describe quick photo/barcode/text logging, editable meal breakdowns, saved
repeat meals, clear daily balances and Israeli product coverage. They are product
references, not access to private implementations or independent evidence of their
speed, accuracy or complete database coverage. We implement our own flows.

The user's objective is comparable usefulness and polish, not a claim that two
fixed bugs establish parity. Each improvement should be usable in the app and
checked from entry to diary persistence. Code is released only via Git PR merges.

| Area | Current evidence | Next acceptance check |
| --- | --- | --- |
| Photo logging | Full-frame upload, captured-image progress, automatic single save, corrected prepared-food labels; mocked browser flows and selected live diagnostics | Representative real image/ingredient/weight evaluation; record p50/p95 end-to-end latency, failures and false ingredients |
| Text corrections | Visible at the top of meal details; diary photo/edit actions reach it; retries preserve text and version checks | Continue device/keyboard checks and mixed-source correction cases |
| Manual ingredient fixes | Quick removal/undo and add-food flow in meal details in this increment | Add/remove/undo must update totals on the same meal, preserve source/amounts of other items, and never overwrite a later edit |
| Product amount | g/ml or weighed units before adding, both barcode paths; exact source per100 preserved; AI-disabled browser checks | Expand verified local coverage and trustworthy unit metadata without guessing density or missing labels |
| Repeat meals/favorites | Add meal → Previous meal offers Recent/Favorites tabs; bookmarks in meal details/history use existing owner-scoped diary data; reuse retains mixed g/ml snapshots, source versions and stable retry IDs | Favorites reference diary entries rather than independent recipes; deleting a bookmarked entry also removes that favorite, explained in the delete confirmation. Continue device and offline checks |
| Visual consistency | Shared sheets, typography, date picker, low-copy choices; Hebrew/English mobile screenshots | Keep checking small screens, keyboard, failed camera/image/network, empty and loading states |
| Independent image models | A CPU public total-mass research candidate exists; it is not production-qualified and does not estimate ingredient masses | Ingredient-level weighed training/evaluation and complete-pipeline comparison before replacing hosted inference |
| Data integrity | Private owner-scoped storage, existing offline queue and optimistic version guards | Cover failed saves, undo after subsequent edits, repeated taps, changed owners and source provenance |

No social feed, smartwatch integration or unrequested commercial infrastructure is
introduced as a shortcut to claiming parity. No invented diary history, accuracy
percentages or progress percentages are shown. Model quality and UX quality are
tracked separately. Private images are not training data without separate consent.

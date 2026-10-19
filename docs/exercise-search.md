# Exercise search

Library and program-builder search share ExerciseSearch, with behavior matching
Android. Matching tolerates punctuation, accents, capitalization, word order,
known plurals and bounded typos such as `sqaut` and `dumbell`. Literal matches
precede corrected matches, and the typed query is preserved. Exact names always
win, including custom exercise names.

Muscle/equipment discovery uses reviewed primary anatomy: `abs` finds core work,
`chest dumbbell` finds chest exercises, and explicit names such as `back squat`
remain searchable. Filters stay strict. Both apps cache prepared Library search
candidates and invalidate them for catalogue and language changes.

All 300 keyword arrays match Android, including five-language names, vendor
names/equipment, abbreviations, single-arm/one-arm wording and exact flat-bench
aliases. The shared exporter changes only search metadata; exercise identities,
saved workouts, backups and media mappings are unaffected.

See the [shared search contract](../../docs/design/exercise-search.md) for edit
limits, ranking, alias maintenance and regression coverage.

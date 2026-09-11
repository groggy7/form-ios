# Exercise search

The library and program-builder picker share `ExerciseSearch`, matching Android.
Names tolerate case, punctuation, repeated spaces and accents (including Turkish
İ/ı). Query words can be reordered and match word prefixes; every word must match.
Exact names rank ahead of name prefixes/phrases, reordered name tokens, and helper
keywords. ExercisePriority retains stable ordering for ties and empty queries.

The canonical `exercises.json` has the same optional `searchKeywords` arrays as
Android: both language names, vendor names/equipment and explicit aliases such as
DB, RDL, OHP, pushdown and pressdown. The Android repository script
`scripts/update_exercise_search_keywords.cjs` emits a patch for both catalogues.
It does not change workout data, canonical IDs, deduplication or media mappings.
Missing keywords decode as an empty array. Custom exercise names remain searchable.

Focused tests: `testFlexibleExerciseSearch` and
`testSearchKeywordsAndCustomExerciseCompatibility`. Shared rationale and rules:
Android repository `docs/design/exercise-search.md`.

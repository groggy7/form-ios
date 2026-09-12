# Exercise muscle panel

`ExerciseMusclesCard.swift` renders the same curated catalogue, grayscale bases,
region geometry and role colors as Android. It is placed immediately below the
exercise video without reordering the existing title/cue sections. It is collapsible
(collapsed by default for scanning, with an animated chevron on tap). Front/back
selection is manual and resets when the exercise changes. Narrow widths and
large text use stacked presentation. Unknown/unreviewed canonical IDs show an
unavailable message instead of guessed targets.

The `ExerciseMuscles` resource folder contains `catalog.json`, `front.png` and
`back.png`, mechanically exported by the Android repository's
`scripts/export_exercise_muscles.cjs`. The master, prompt, sources and export
contract are preserved there in `docs/design/exercise-muscles.md` and its sibling
`exercise-muscles/` directory. Do not independently edit iOS copies.

Initial scope: 16 curated exercises. Primary/secondary roles are illustrative
editorial mappings, not clinical assessment or measured activation. Some muscle
regions are shown over shorts. No personal data migrations, paid gates, changes
to exercise videos, or changes to Today artwork.

Verification 2026-09-12: two focused catalogue and native-render tests passed on
iPhone 17 Pro Max simulator, including 280pt Turkish Dynamic Type XXXL, normal
350pt cards, lower-body focus and unknown-ID fallback. Android's matching panel
passed three focused physical-phone UI tests. Shared resource bytes match.

# Archived exercise animation system

Retired 2026-09-11. This directory is outside the Xcode target's sources and
resource catalogue; nothing here is bundled.

Original paths are preserved:

- `FormApp/Resources/Assets.xcassets/`: all 58 old exercise imagesets, including
  their PNG bytes and Contents.json metadata.
- `FormApp/Views/Components/MovementIcon.swift`: historical renderer, frame cache,
  resource mappings and animation clocks.
- `FormAppTests/FormAppTests.swift`: pre-retirement test-file snapshot (the live
  file retains non-animation tests and now checks empty media frames).

The Android repository's `archive/legacy-exercise-animation/` holds shared
masters, prompts, registration/export scripts, review images and provenance.
Files were moved with SHA-256 verification, not regenerated or deleted.
Restore only in an isolated checkout; do not add this archive to Xcode resources.

Current exercise media areas intentionally remain empty. Exercise definitions,
stored IDs, personal history, Today artwork and other app resources are unchanged.

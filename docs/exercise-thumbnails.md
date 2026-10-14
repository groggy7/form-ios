# Static STEP1 thumbnails

Approved 2026-09-11. `FormApp/Resources/ExerciseThumbnails/` is an explicit Xcode
folder resource containing 300 transparent static PNGs and `catalog.json`.
It is byte-identical to Android's `app/src/main/assets/exercise_thumbnails/`.
STEP2, original source packs and legacy sprite assets are not bundled.

The shared importer `scripts/import_exercise_thumbnails.cjs` in the Android repo
selects the purchased pack's matching STEP1 view using the video catalogue.
It trims only fully transparent outer space, proportionally resizes inside
368×368, adds 8px transparent padding, and exports PNG compression level 9.
The catalogue preserves source filenames/hashes/dimensions, crop bounds and
output dimensions/hashes. The 300 PNGs total 24,203,332 bytes.

MovementIcon and MovementIllustration show one static fitted image on the
thumbnail backdrop elliptical gradient (`#064844` → `#052B2C` → `#051216`, matching the video studio spotlight), with an 8 MiB decoded-image cache.
Lookup is by canonical exercise ID, never translated name or old artwork alias.
Unknown custom exercises remain blank. Detail video playback, crop metadata,
`#16202A` video surface, prescriptions and personal workout data are unchanged.

Bundled thumbnails and studio backdrops decode through ImageIO with immediate
caching on their serial worker queues. UIKit's `preparingForDisplay()` produces
`Error -17102 decompressing image -- possibly corrupt` for these valid PNGs;
the ImageIO path avoids that warning while preserving decoded color, alpha,
dimensions and the existing 8 MiB caches. A native audit confirmed all 300 STEP1
files and seven backdrops match their recorded hashes and decode successfully.

Focused iOS tests verify complete thumbnail coverage, dimensions, transparency,
blank unknown exercises, native rendering, and unchanged video mapping/framing.
The PNG decoder regression compares all 307 images pixel-for-pixel, and the Home
fixture switches between days with one, four and six exercises, then revisits a
cached day in Obsidian and Oat.
The native rendered sample is in `thumbnail-reviews/static-thumbnails-ios.png`.
Full shared provenance: Android repo `docs/design/exercise-thumbnails.md`.

# Exercise detail videos

The 300 local MP4 files in `FormApp/Resources/ExerciseVideos/` replace only the
exercise-detail banner. Library thumbnails now use separate
[static STEP1 images](exercise-thumbnails.md). The video folder is an
explicit Xcode resource; the legacy archive is not bundled.

`catalog.json` maps stable canonical exercise IDs to source video IDs, filenames,
vendor metadata and SHA-256 hashes. Files are copied without transcoding from
the Android repository's user-processed `ready/` folder using
`scripts/import_ready_exercise_videos.cjs` in that repository. See its
`docs/design/exercise-detail-videos.md` for the shared provenance and mapping.

The 1280×720 H.264 videos have no audio tracks and total 96,144,169 bytes.
The detail banner uses `#16202A` while loading, then fills edge-to-edge with the
decoded video. `framing.json` is byte-identical to Android's full-motion-safe
crop metadata for all 300 exercises. The card follows the crop's aspect ratio,
without the previous 12pt padding or fixed 224pt height. An oversized, offset
AVPlayerLayer inside a clipped view applies the fixed crop without stretching,
animated zoom or panning. The rounded card and border remain.
AVPlayerLooper loops silently at 1.2× speed without activating audio.
Playback pauses for inactive scenes, disappeared detail views, reduced motion
and view removal, and resources are released on dismissal.

The original focused native tests covered catalogue URLs, real playback/pause,
crop geometry at 320pt and 440pt widths, the actual SwiftUI card height,
and the then-empty thumbnail renderer. Thumbnails now use the separate static STEP1
system linked above. Existing workout data and cues are not
migrated or replaced with vendor metadata.

The Android repository's `scripts/measure_exercise_video_framing.cjs` measures
all frames and updates both platforms' crop metadata. No videos were regenerated
or re-encoded for this change.

At the original 50-video rollout, all four focused checks passed on iPhone 17 Pro Max Simulator; the updated app
was installed in place. The native render is preserved at
[bench-video-full-bleed-ios.png](video-reviews/bench-video-full-bleed-ios.png).
The current 300-video framing JSON SHA-256 (verified on both platforms) is
`1728ac511990f54bfb215a3df75aa8e67a0b8b376cf2fea068b73995b57bff90`.

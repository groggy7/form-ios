# Exercise detail videos

The 50 local MP4 files in `FormApp/Resources/ExerciseVideos/` replace only the
exercise-detail banner. Library thumbnails remain empty. The folder is an
explicit Xcode resource; the legacy archive is not bundled.

`catalog.json` maps stable canonical exercise IDs to source video IDs, filenames,
vendor metadata and SHA-256 hashes. Files are copied without transcoding from
the Android repository's user-processed `ready/` folder using
`scripts/import_ready_exercise_videos.cjs` in that repository. See its
`docs/design/exercise-detail-videos.md` for the shared provenance and mapping.

The 1280×720 H.264 videos have no audio tracks and total 16,166,911 bytes.
The detail banner uses `#16202A` to match their background. AVPlayerLayer fits
the whole image; AVPlayerLooper loops silently without activating audio.
Playback pauses for inactive scenes, disappeared detail views, reduced motion
and view removal, and resources are released on dismissal.

The three focused native tests verify all catalogue URLs, real playback/pause,
and unchanged empty thumbnail rendering. Existing workout data and cues are not
migrated or replaced with vendor metadata.

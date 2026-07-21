# FFMpegasus Media Fixtures

This directory documents the synthetic media fixtures used by optional FFmpeg-backed tests.

The fixtures exist so media behavior is reproducible across trim, playback, frame export,
interval export, speed, transform, compression, and combined-export tests. All fixture media is
generated locally with FFmpeg. No fixture uses downloaded, third-party, or copyrighted media.

## Directory Layout

```text
Tests/Fixtures/
  README.md
  manifest.json
  generated/
    .gitkeep
```

`manifest.json` is the authoritative description of expected fixture metadata. Generated media
files are written to `Tests/Fixtures/generated/` and are ignored by Git.

## Prerequisites

Install FFmpeg and FFprobe. The generator resolves tools in this order:

1. `FFMPEG` and `FFPROBE` environment variables
2. `/opt/homebrew/bin/ffmpeg` and `/opt/homebrew/bin/ffprobe`
3. `ffmpeg` and `ffprobe` on `PATH`

The script also uses `python3` for JSON and FFprobe validation.

## Commands

Generate or regenerate all fixtures:

```bash
make fixtures
```

Validate existing generated fixtures:

```bash
make fixtures-validate
```

Remove generated fixture media:

```bash
make fixtures-clean
```

Run fixture-backed integration tests as part of the full suite:

```bash
swift test
```

Run the complete validation sequence:

```bash
swift package clean
swift test
swift build
```

## Generated Versus Committed Policy

Committed:

- `README.md`
- `manifest.json`
- generation and validation script
- `.gitkeep`

Not committed:

- generated `.mp4`, `.mov`, and `.mkv` media files
- temporary working files
- partial outputs

The generator writes through `.partial` files and moves them into place only after FFmpeg creates
a nonempty output. It is safe to run repeatedly.

## Fixture Set

The fixture manifest currently defines:

- `standard-landscape.mp4`: landscape H.264/AAC CFR video, default general-purpose fixture.
- `silent-video.mp4`: H.264 video with no audio stream.
- `portrait-video.mp4`: physically portrait-coded H.264/AAC video.
- `rotation-metadata.mov`: landscape coded pixels with verified 90-degree display-matrix rotation.
- `variable-frame-rate.mkv`: H.264 video with verified nonuniform presentation timestamp deltas and a preserved timestamp gap between segments.
- `unusual-dimensions.mp4`: H.264/AAC video with valid uncommon even dimensions.
- `frame-identifiable.mp4`: one-second color-coded segments for frame/seek checks.

See `manifest.json` for codec, dimensions, duration, rotation, timing, and intended test usage.

## Validation

After generation, the script probes every fixture with FFprobe and checks:

- required video stream exists
- audio stream presence matches the manifest
- codec, coded dimensions, duration, and rotation metadata match expectations
- generated files are nonempty
- `rotation-metadata.mov` contains actual rotation metadata
- `variable-frame-rate.mkv` has at least two distinct positive frame timestamp deltas

The script exits nonzero if any fixture does not match the manifest.

## Test Usage

Tests locate fixtures relative to the Swift package root. They may generate missing fixtures when
FFmpeg and FFprobe are available. Fixture files are treated as read-only; tests write outputs to
their own temporary directories.

## Adding A Fixture

1. Add one entry to `manifest.json`.
2. Add a generator function in `scripts/fixtures.sh`.
3. Add validation that proves any special behavior.
4. Document the fixture purpose here.
5. Keep the fixture small and synthetic.

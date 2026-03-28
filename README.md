# ffmpeg-audio-build

[中文说明](README_zh.md)

This repository builds audio-focused `ffmpeg` and `ffprobe` binaries with GitHub Actions.

Current targets:

- `aarch64-apple-darwin`
- `x86_64-apple-darwin`
- `x86_64-unknown-linux-gnu`
- `aarch64-unknown-linux-gnu`
- `x86_64-pc-windows-msvc`
- `aarch64-pc-windows-msvc`

Project goals:

- Keep only audio-related functionality
- Statically link third-party audio dependencies
- Avoid third-party codec runtime libraries in the final artifacts
- Validate every target on a matching platform runner

Current workflows:

- `.github/workflows/build-audio-mac-arm64.yml`
- `.github/workflows/build-audio-mac-x86_64.yml`
- `.github/workflows/build-audio-linux-x86_64.yml`
- `.github/workflows/build-audio-linux-aarch64.yml`
- `.github/workflows/build-audio-windows-x86_64.yml`
- `.github/workflows/build-audio-windows-aarch64.yml`

Reusable workflow:

- `.github/workflows/reusable-build-audio-target.yml`

How to trigger a build:

1. Open GitHub Actions.
2. Choose the workflow for the target triple you want.
3. Run it with `workflow_dispatch`.
4. The default FFmpeg ref is `n8.1`.

Artifact contents:

- `ffmpeg` or `ffmpeg.exe`
- `ffprobe` or `ffprobe.exe`
- `BUILD_INFO.txt`
- `CONFIGURE_ARGS.txt`

Validation steps:

- Verify binary architecture and minimum OS version
- Check that no third-party runtime libraries remain
- Verify that `ffmpeg` and `ffprobe` start correctly
- Verify audio transcoding:
  `wav -> mp3`
  `wav -> aac`
  `aac -> mp3`
- Verify audio clipping:
  `wav -> clip.wav`, then confirm the clipped duration

Notes:

- macOS and Linux targets build `lame`, `libogg`, `libvorbis`, and `opus` from source as static dependencies before building `ffmpeg` and `ffprobe`.
- Windows targets use the MSVC toolchain plus a static dependency prefix, and validation checks that no third-party DLLs are required at runtime.
- The goal is to keep audio transcoding and audio clipping working, not to produce a full general-purpose multimedia FFmpeg build.
- The current smoke tests use AAC in ADTS format instead of `m4a/ipod`.

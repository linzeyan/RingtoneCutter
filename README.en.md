<p align="center">
  <img src="RingtoneCutter/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="128" alt="Ringtone Cutter icon">
</p>

<h1 align="center">Ringtone Cutter</h1>

<p align="center">Turn any song into an iPhone ringtone</p>

<p align="center"><a href="README.md">正體中文</a> · English</p>

---

Ringtone Cutter trims the music you already have into a ringtone of up to 30 seconds — no computer, no GarageBand.

## Features

- **Three sources**:
  - Choose File: music or video from the Files app, including iCloud Drive, Google Drive, Dropbox and OneDrive.
  - Choose Video: a video from Photos, screen recordings included.
  - Paste a Link: no cloud drive app needed. Paste a public share link from Google Drive, Dropbox or OneDrive and the file downloads by itself; direct download links such as S3 work too.
- **Trim by the waveform**: a strip of the whole song to jump between sections, and a zoomed 60-second waveform with drag handles and ±0.1 s nudges. The clip never runs past the 30-second ringtone limit.
- **Hear it before you make it**: the playhead moves across the waveform; fade in and out is on by default, and what you preview is exactly what you get.
- **One tap to set it**: tap Make Ringtone, name it, and the share sheet opens — tap "Use as Ringtone" (iOS 26 and later).
- **iCloud sync**: switch the save location at the top right from iPhone to iCloud, and finished ringtones are saved to the Ringtone Cutter folder in iCloud Drive, ready on a new iPhone, an iPad or a Mac. The iPhone ringtone list itself doesn't sync, so on another iPhone open the file from Files and tap "Use as Ringtone".
- **Common formats**: MP3, M4A, AAC, WAV, AIFF, FLAC, ALAC, Opus and AC-3, plus the sound from MP4 and MOV videos. Audio in other apps can be opened straight in Ringtone Cutter.
- **Nothing collected**: no ads, no account, no in-app purchases; the app goes online only to download a link you paste. See the [privacy policy](PRIVACY.md).

## Requirements

- iPhone with iOS 18 or later.
- "Use as Ringtone" needs iOS 26 or later. On iOS 18–25 you can still trim and make ringtones; they are saved in Files → On My iPhone → Ringtone Cutter and need syncing from a computer.

## Support

Please open an [issue](https://github.com/linzeyan/RingtoneCutter/issues).

## Development

SwiftUI, no third-party dependencies. The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and is not committed.

```bash
make setup         # install XcodeGen if needed, generate RingtoneCutter.xcodeproj
make test          # unit tests on the iPhone simulator
make run           # build and launch on the simulator
make run-device    # build, install and launch on the paired iPhone (DEVICE_ID)
make icon          # render design/AppIcon.svg into the asset catalog (rsvg-convert)
make screenshots   # App Store screenshots, zh-Hant and en (needs ffmpeg)
make release       # Release archive + App Store IPA in build/export/
```

| Path | |
| --- | --- |
| `RingtoneCutter/` | App source, string catalogs (`zh-Hant` source, `en`), privacy manifest |
| `RingtoneCutterTests/` | Unit tests: clip limits, trimming, fades, waveform levels, share-link rewriting |
| `RingtoneCutterUITests/` | Store screenshot walk, run only by `make screenshots` |
| `design/AppIcon.svg` | Source of the app icon |
| `scripts/` | Screenshot simulator setup and attachment renaming |
| `samples/demo.m4a` | Synthesized 60 s track for trying Paste a Link |

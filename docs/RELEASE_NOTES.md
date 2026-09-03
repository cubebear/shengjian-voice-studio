# ShengJian 0.1.0 — Experimental release

**English** | [简体中文](https://github.com/cubebear/shengjian-voice-studio/blob/main/docs/RELEASE_NOTES.zh-CN.md)

[Project overview](https://github.com/cubebear/shengjian-voice-studio#readme) · [中文项目说明](https://github.com/cubebear/shengjian-voice-studio/blob/main/README.zh-CN.md) · [中文使用教程](https://github.com/cubebear/shengjian-voice-studio/blob/main/%E4%BD%BF%E7%94%A8%E8%AF%B4%E6%98%8E.md)

A local voice studio for Intel Macs, with voice cloning, manuscript import, segmented generation, audio adjustments, and a choice of ModelScope or Hugging Face for model downloads. Once the model is available locally, generation does not require Python, Docker, or Homebrew. The desktop interface is currently in Chinese.

## Included in 0.1.0

This is the first experimental application release, not just a source-code snapshot.

- Native Intel Mac desktop studio with bundled AVX2 and compatibility engines, automatic runtime setup, and repair.
- Local voice cloning from an authorized recording, with reusable voice profiles.
- TXT, Markdown, and RTF import; segmented generation, individual segment regeneration, and WAV export.
- Audio trimming, gain, normalization, fades, speed, and pitch adjustments.
- ModelScope or Hugging Face downloads with revision pins, resume support, size/hash checks, and existing-model directory import.

## Downloads

| File | Purpose |
|---|---|
| [ShengJian-Intel-0.1.zip](https://github.com/cubebear/shengjian-voice-studio/releases/download/v0.1.0/ShengJian-Intel-0.1.zip) | Intel Mac application — download this to run ShengJian |
| [ShengJian-Source-0.1.zip](https://github.com/cubebear/shengjian-voice-studio/releases/download/v0.1.0/ShengJian-Source-0.1.zip) | Source package with the vendored engine and license notices |
| [SHA256SUMS.txt](https://github.com/cubebear/shengjian-voice-studio/releases/download/v0.1.0/SHA256SUMS.txt) | SHA-256 checksums for the downloadable files |
| [USER_GUIDE.zh-CN.md](https://github.com/cubebear/shengjian-voice-studio/releases/download/v0.1.0/USER_GUIDE.zh-CN.md) | Detailed user guide in Chinese |
| [VERIFICATION.zh-CN.md](https://github.com/cubebear/shengjian-voice-studio/releases/download/v0.1.0/VERIFICATION.zh-CN.md) | Validation report in Chinese |
| [screenshot.png](https://github.com/cubebear/shengjian-voice-studio/releases/download/v0.1.0/screenshot.png) | Desktop interface preview |

**Model weights are not included.** The small application archive contains the interface and native runtime; download or import a model separately. The starter 0.6B Base model requires about 2.52 GB of model files.

## Installation

1. Download `ShengJian-Intel-0.1.zip` and `SHA256SUMS.txt` from the table above. Check the application's SHA-256 before opening it.
2. Extract the archive, move `ShengJian-Intel.app` into Applications, and open it.
3. Wait for the local engine to become ready. In model management, choose ModelScope or Hugging Face and download **0.6B Base**, or import a complete supported model directory.
4. Select your own or explicitly authorized reference recording, enter its transcript, and generate one short sentence before trying a long manuscript.

The app is ad-hoc signed, without Apple Developer ID signing or notarization. Only allow this individual app through macOS security controls after confirming its source and hash. Do not disable Gatekeeper globally.

## Before you start

- The compilation target is macOS 10.15 / x86_64. **A 2019 Mac Pro and older macOS releases have not been tested.**
- Completed validation includes real 0.6B Base inference under Rosetta, 26 core checks, numerical self-tests for both engines, and runtime repair checks.
- The reference audio was computer-synthesized. Cloning similarity to your own voice has not been evaluated, and Rosetta timings do not predict performance on Intel hardware.
- The 1.7B, CustomVoice, VoiceDesign, and experimental controls have not all completed real generation validation. Hugging Face downloading still needs verification on the target network.
- This version provides inference only, without training, GPU acceleration, or real-time streaming.

Use only your own or explicitly authorized voices, and disclose that shared audio is synthetic. The source and release packages contain no personal recordings, voice profiles, or model weights. Third-party licenses and notices are retained.

See the [README](https://github.com/cubebear/shengjian-voice-studio#readme), [Chinese user guide](https://github.com/cubebear/shengjian-voice-studio/blob/main/%E4%BD%BF%E7%94%A8%E8%AF%B4%E6%98%8E.md), [validation report (Chinese)](https://github.com/cubebear/shengjian-voice-studio/blob/main/%E9%AA%8C%E8%AF%81%E6%8A%A5%E5%91%8A.md), and [third-party notices (Chinese)](https://github.com/cubebear/shengjian-voice-studio/blob/main/THIRD_PARTY_NOTICES.md).

The application and source archives correspond to the original `v0.1.0` tag. This release-notes revision does not change the binaries, checksums, or tag. Use the repository links above for the latest English and Chinese documentation.

# ShengJian 0.1.0 — Experimental release

**English** | [简体中文](https://github.com/cubebear/shengjian-voice-studio/blob/main/docs/RELEASE_NOTES.zh-CN.md)

[Project overview](https://github.com/cubebear/shengjian-voice-studio#readme) · [中文项目说明](https://github.com/cubebear/shengjian-voice-studio/blob/main/README.zh-CN.md) · [中文使用教程](https://github.com/cubebear/shengjian-voice-studio/blob/main/%E4%BD%BF%E7%94%A8%E8%AF%B4%E6%98%8E.md)

A local voice studio for Intel Macs, with voice cloning, manuscript import, segmented generation, audio adjustments, and a choice of ModelScope or Hugging Face for model downloads. Once the model is available locally, generation does not require Python, Docker, or Homebrew. The desktop interface is currently in Chinese.

## Installation

Download **[ShengJian-Intel-0.1.zip](https://github.com/cubebear/shengjian-voice-studio/releases/download/v0.1.0/ShengJian-Intel-0.1.zip)**, verify it against **[SHA256SUMS.txt](https://github.com/cubebear/shengjian-voice-studio/releases/download/v0.1.0/SHA256SUMS.txt)**, extract it, and open the application. Model weights are not included. For a first test, download **0.6B Base** from ModelScope or Hugging Face in the model management screen.

The app is ad-hoc signed, without Apple Developer ID signing or notarization. Only allow this individual app through macOS security controls after confirming its source and hash. Do not disable Gatekeeper globally.

## Before you start

- The compilation target is macOS 10.15 / x86_64. **A 2019 Mac Pro and older macOS releases have not been tested.**
- Completed validation includes real 0.6B Base inference under Rosetta, 26 core checks, numerical self-tests for both engines, and runtime repair checks.
- The reference audio was computer-synthesized. Cloning similarity to your own voice has not been evaluated, and Rosetta timings do not predict performance on Intel hardware.
- The 1.7B, CustomVoice, VoiceDesign, and experimental controls have not all completed real generation validation. Hugging Face downloading still needs verification on the target network.
- This version provides inference only, without training, GPU acceleration, or real-time streaming.

Use only your own or explicitly authorized voices, and disclose that shared audio is synthetic. The source and release packages contain no personal recordings, voice profiles, or model weights. Third-party licenses and notices are retained.

See the [README](https://github.com/cubebear/shengjian-voice-studio#readme), [Chinese user guide](https://github.com/cubebear/shengjian-voice-studio/blob/main/%E4%BD%BF%E7%94%A8%E8%AF%B4%E6%98%8E.md), [validation report (Chinese)](https://github.com/cubebear/shengjian-voice-studio/blob/main/%E9%AA%8C%E8%AF%81%E6%8A%A5%E5%91%8A.md), and [third-party notices (Chinese)](https://github.com/cubebear/shengjian-voice-studio/blob/main/THIRD_PARTY_NOTICES.md).

This update changes online documentation and navigation only. The original 0.1.0 application, source attachment, checksums, and version tag remain unchanged. Use the repository links above for the latest English and Chinese documentation.

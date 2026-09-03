# ShengJian

**English** | [简体中文](README.zh-CN.md)

[Download](https://github.com/cubebear/shengjian-voice-studio/releases/tag/v0.1.0) · [Quick start](#quick-start) · [中文使用教程](使用说明.md) · [Release notes](docs/RELEASE_NOTES.md)

A local voice cloning and text-to-speech studio for Intel Macs. Use your own recording as a voice reference, import a manuscript, regenerate individual segments, adjust audio, and export WAV files from a desktop interface.

**Version 0.1.0 is experimental.** The application targets Intel x86_64 and macOS 10.15 at build time, but has **not** been tested on a 2019 Mac Pro or older macOS releases. The completed inference test ran on Apple Silicon through Rosetta; it does not establish performance or voice similarity on Intel hardware. The desktop interface is currently in Chinese.

This is an independent community project using [Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS) models and the C inference implementation from [gabriele-mastrapasqua/qwen3-tts](https://github.com/gabriele-mastrapasqua/qwen3-tts). It is not an official Qwen application and is not affiliated with or endorsed by the model publisher.

![ShengJian desktop interface](docs/screenshot.png)

## Features

- **Local voice cloning:** import your own or an explicitly authorized recording and its transcript; save and reuse voice profiles.
- **Manuscript to audio:** import TXT, Markdown, and RTF with common Chinese text encodings; split text into segments, regenerate individual segments, merge, and export WAV.
- **Audio adjustments:** trim, change gain, normalize peaks, add fades, and adjust speed or pitch. Adjusted audio is saved as a copy.
- **Model management:** choose ModelScope (mainland China, the default) or Hugging Face; resume downloads, pin revisions, and verify file sizes and hashes. Import an existing complete official model directory as an alternative.
- **Inference controls:** language, CPU threads, quantization, sampling parameters, random seed, reference audio, and selected advanced options.
- **Automatic runtime setup:** bundled native C engines are verified and installed into the application's own data directory on first launch, and repaired if damaged. No Python, PyTorch, Docker, or Homebrew installation is needed to run the app. It does not automatically change the system environment.

This version does not provide training, fine-tuning, GPU acceleration, real-time streaming, arbitrary model architecture support, or an online voice service. Its interface covers the inference features integrated into this project, not every upstream model or CLI capability.

## Quick start

Download `ShengJian-Intel-0.1.zip` and `SHA256SUMS.txt` from [Releases](https://github.com/cubebear/shengjian-voice-studio/releases), or build from source as described below.

1. Verify the archive's SHA-256, extract it, and move `ShengJian-Intel.app` into Applications.
2. The app is ad-hoc signed, without Apple Developer ID signing or notarization. After verifying its source and hash, use Finder's **Open** command or the system security settings to allow this individual app if macOS blocks it. Do not disable Gatekeeper globally. If macOS reports a damaged file, download it again and verify it first.
3. Launch the app and wait for **“本地引擎就绪”** (local engine ready). **“环境与帮助”** (environment and help) shows diagnostics.
4. In **“模型管理”** (model management), choose a download source and start with **0.6B Base**. The required files total about 2.52 GB; allow at least 5 GB for downloads and temporary files.
5. Prepare a clean recording with only your voice and no background music. Select it in the studio and enter its exact transcript.
6. Generate one short sentence with the initial settings, listen to the result, and then try longer text. CPU generation may be substantially slower than the duration of the resulting audio.

The [detailed user guide in Chinese](使用说明.md) covers installation, recording preparation, parameters, model directory structure, segment editing, and troubleshooting.

## Hardware and validation

| Item | Current status |
|---|---|
| Intended hardware | Intel Macs, with a focus on CPU inference on the 2019 Mac Pro |
| Minimum compilation target | macOS 10.15; this is not a verified minimum supported OS |
| CPU engines | AVX2/FMA and a compatibility engine; the latter is selected when AVX2 is not detected |
| Memory | At least 16 GB is recommended as a starting point, with more for larger models and longer text; not measured on the target hardware |
| Graphics | The Mac Pro's AMD GPU is not used by this version |
| Tested environment | Apple Silicon, macOS 26.6.2, running the x86_64 app through Rosetta |
| Tested model inference | 0.6B Base with a computer-synthesized reference, producing a valid 3.36-second WAV |
| Other checks | 26 core checks passed; both engine numerical self-tests, native startup, and runtime repair passed |

The 1.7B, CustomVoice, VoiceDesign, and some experimental controls are integrated but have not all been validated through full model downloads and generation. Hugging Face manifest handling was tested, but large-file downloading timed out on the test network. A real 0.6B Base download from ModelScope completed and passed validation. See the [validation report in Chinese](验证报告.md).

## Models and download sources

Model weights are **not bundled with the source code or application**. Downloading contacts the selected platform and its file CDN; the app does not silently switch platforms. Availability in mainland China still depends on location, network provider, and time, and is not guaranteed.

| Model | Purpose | ModelScope | Hugging Face |
|---|---|---|---|
| 0.6B Base | Recommended starting point for voice cloning | [Download](https://modelscope.cn/models/Qwen/Qwen3-TTS-12Hz-0.6B-Base) | [Download](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base) |
| 1.7B Base | Larger voice cloning model | [Download](https://modelscope.cn/models/Qwen/Qwen3-TTS-12Hz-1.7B-Base) | [Download](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-Base) |
| 0.6B CustomVoice | Preset speakers | [Download](https://modelscope.cn/models/Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice) | [Download](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice) |
| 1.7B CustomVoice | Preset speakers and style instructions | [Download](https://modelscope.cn/models/Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice) | [Download](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice) |
| 1.7B VoiceDesign | Design a voice using a text description | [Download](https://modelscope.cn/models/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign) | [Download](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign) |

Imports require a **complete official BF16 safetensors directory**. A standalone weight file, Git LFS pointer, GGUF file, or MLX conversion is not supported. The quantization setting applies inside the inference engine at runtime. Model licenses are independent of the application license; follow each model repository's license and notices.

## Privacy, consent, and security

Recordings, manuscripts, voice profiles, and generated audio are stored locally under `~/Library/Application Support/ShengJianStudio`. The app does not implement cloud inference or telemetry and does not proactively upload this content. Model downloads expose ordinary network request information to the selected service. System backups, synchronization, browser behavior, and sharing initiated by the user are outside this project's control.

Clone only your own voice or a voice you have explicit permission to use. Clearly disclose that shared audio is synthetic. Do not use it for fraud, deceptive impersonation, or bypassing voice authentication. Voice vectors and `.qvoice` files also need protection. A `.qvoice` file may contain some source model weights, so sharing one requires considering both voice consent and the model license.

The [responsible-use guidance (Chinese)](RESPONSIBLE_USE.md) explains risks without adding field-of-use restrictions to the MIT license. An open-source license does not grant rights to anyone's voice, likeness, or identity. Do not import untrusted model or voice files: the third-party native parsers have not undergone a complete security audit. See the [security and privacy notes (Chinese)](SECURITY.md).

## Build from source

Building requires macOS, Xcode Command Line Tools, and Python 3. These are **build dependencies**; the resulting application does not need Python to run.

```bash
python3 build.py
```

The output is `dist/ShengJian-Intel.app`. The script builds both Intel engines from the bundled, pinned source snapshot, compiles Swift, packages the local interface and licenses, and ad-hoc signs the app. It does not download models, notarize, or publish anything.

Run the core checks with:

```bash
mkdir -p .build/test-cache .build/test-artifacts
xcrun swiftc -swift-version 5 -target x86_64-apple-macos10.15 \
  -module-cache-path .build/test-cache -framework AVFoundation \
  Sources/Core.swift Sources/Download.swift Tests/main.swift \
  -o .build/core-tests
.build/core-tests "$PWD/.build/test-artifacts" "$PWD/Tests/Fixtures"
```

Audio checks require macOS audio services in a normal desktop session. Running these Intel tests on Apple Silicon also requires Rosetta. The [build and architecture notes](docs/BUILD.md) describe the QA build entry point. `Verification/` contains historical test evidence, not a guarantee that every device will pass.

## Documentation / 中文说明

| English | 简体中文 |
|---|---|
| [Project overview](README.md) | [项目说明](README.zh-CN.md) |
| [Release notes](docs/RELEASE_NOTES.md) | [发行说明](docs/RELEASE_NOTES.zh-CN.md) |
| [Quick start](#quick-start) | [完整使用教程](使用说明.md) |
| [Hardware and validation](#hardware-and-validation) | [验证报告](验证报告.md) |

The interface and the existing detailed Chinese guides remain unchanged. Use the language links at the top of each overview or release-notes page to switch languages.

## License and acknowledgements

The original interface, Swift wrapper, and build scripts are licensed under [MIT](LICENSE). Third-party code in `Vendor/` retains its own licenses; the root MIT license does not replace them. This includes the C inference engine, ingot, tables derived from llama.cpp/ggml, LZ4, and KleidiAI notices retained with the source. See [third-party notices (Chinese)](THIRD_PARTY_NOTICES.md).

Qwen3-TTS models are published by the Qwen team under their separate Apache-2.0 license. Thanks to all upstream contributors. This project is provided as is, without guarantees of hardware compatibility, cloning quality, or suitability for a particular purpose.

When reporting a problem, include the application version, macOS version, CPU and memory, selected model, and redacted error information. Do not post private recordings, voice profiles, complete manuscripts, or credentials in public issues.

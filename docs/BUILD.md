# ShengJian / 声笺 0.1

Native AppKit + WKWebView studio, with a bundled Intel C Qwen3-TTS engine.
No Python, Docker, Homebrew or web server is used by the delivered application.

The compile target is x86_64 macOS 10.15 with AVX2/FMA CPU kernels and a scalar fallback. The app selects the fallback when the runtime does not report AVX2. Actual older
macOS releases and Intel Mac Pro hardware still need acceptance testing.

## Build

On a Mac with Xcode Command Line Tools and Python 3:

```bash
python3 build.py
```

The result is `dist/ShengJian-Intel.app`. The script uses subprocess argument
arrays, builds the pinned vendored engine, compiles Swift against macOS 10.15,
bundles notices and runtime checksums, then ad-hoc signs the result. It does not
notarize or publish the app. Python is only needed to build from source.

The vendor snapshot includes the files needed by the CPU build; source revision
is recorded in `Vendor/qwen3-tts/PINNED_REVISION`. Unused training/demo files and
git metadata are omitted. The engine's upstream Makefile is otherwise unchanged.
The wrapper overrides the C flags to avoid host-native ARM instructions and
`ACCELERATE_NEW_LAPACK`, which requires newer macOS versions.

## Test

From the extracted source directory, in a normal desktop session:

```bash
mkdir -p .build/test-cache .build/test-artifacts
xcrun swiftc -swift-version 5 -target x86_64-apple-macos10.15 \
  -module-cache-path .build/test-cache -framework AVFoundation \
  Sources/Core.swift Sources/Download.swift Tests/main.swift \
  -o .build/core-tests
.build/core-tests "$PWD/.build/test-artifacts" "$PWD/Tests/Fixtures"
```

Audio tests need access to macOS Audio Unit services. In an OS sandbox without
those services, audio component tests may be unavailable. The tests cover text
encodings, WAV roundtrip, crop/fade/gain, time/pitch duration, segmentation,
model/voice checks, subprocess failure/cancellation, parameters, and both source
manifest formats. Fixtures are not proof that remote downloading always works.

A separate native UI smoke build can be produced with `python3 build.py --qa
--output dist/ShengJian-QA.app`. Run its executable with `--data-dir` and an
absolute scratch directory. It checks the native-to-JS bridge, initializes the
real engine, writes a JSON report and screenshot, then exits. Do not distribute
this QA build as the normal app.

## Design

- `Sources/App.swift`: native panels, application lifecycle, jobs, playback.
- `Sources/Core.swift`: validation, child processes, text and audio operations.
- `Sources/Download.swift`: ModelScope and Hugging Face metadata, revision pins,
  download/size/hash checks and source-specific resume files.
- `Resources/ui/`: bundled interface; no external scripts or connections.
- `Tools/Icon.swift`: source for the bundled vector-derived app icon.
- `Tests/`: meaningful core tests and an explicit model download test harness.

The WebKit bridge is restricted to the app's local main frame. Native operations
use allowlisted parameters and direct argument arrays, never shell evaluation.
Downloaded weights are validated; local imports must be trusted. This is not a
full security audit of the third-party model loader.

Settings and user media live under `~/Library/Application Support/ShengJianStudio`.
Only model download actions contact the selected repository/CDN. Network source
switches are explicit. Model weights are not included in this source archive.

Scope: inference only. No training, fine-tuning, real-time audio streaming,
public server, arbitrary model architecture support or GPU backend is exposed.

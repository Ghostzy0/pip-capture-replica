# Set up Pip Capture

Paste into a coding assistant with local terminal access:

> Set up https://github.com/Ghostzy0/pip-capture-replica on my Mac. Read README.md and this setup guide; verify my macOS/Xcode, run the tests, verify the shared-source pin and build the replica, then show me the local apps. Ask me for native microphone consent only if I choose recording. Do not upload recordings, buy anything, or disable system security.

For optional speech:

> Configure Pip Capture for local whisper.cpp using a pinned official source revision and separately licensed Whisper weights. Show the download size/source/hash first, use no paid service or account credentials, run one synthetic file-fed check, then show me the exact executable and weights to choose in Settings.

## Prerequisites and variant checks

Apple Silicon macOS 14+, full Xcode and writable disk. No Homebrew dependency is needed for the app itself. Full Xcode may require owner licence/first-launch acceptance. Read the prompt and complete it personally when required.

```sh
xcode-select -p
swift --version
swift test --jobs 2
python3 scripts/verify-shared-core.py
./scripts/build-replica.sh
(cd baseline && swift test --jobs 2)
./scripts/build-baseline.sh
codesign --verify --deep --strict 'build/Capture Replica.app'
open 'build/Capture Replica.app'
```

Create a synthetic text note, save, quit/reopen, search, export Markdown and move/restore it from Recently deleted. This verifies the local workflow without microphone or cloud access. Native capture requires permission from Start recording. This replica has no Plus compact recorder or tag-filter feature. Complete reference fidelity remains pending. Source build tests do not prove microphone acceptance or recognition quality.

## Optional local transcription

The app deliberately does not run installation scripts or fetch weights. Use only a trusted binary you have built or reviewed. Example reproducible official source build (requires CMake and a C/C++ compiler; install those through your normal trusted route if absent):

```sh
git clone https://github.com/ggml-org/whisper.cpp.git
cd whisper.cpp
git checkout 231638a0717b7822784297e5980965ffcec05810
cmake -B build -DCMAKE_BUILD_TYPE=Release -DWHISPER_BUILD_TESTS=OFF
cmake --build build --config Release --target whisper-cli -j 2
```

The executable is `build/bin/whisper-cli`. Review the upstream MIT notice. Choose an explicitly licensed compatible converted Whisper weight file, verify the exact SHA256 against its source, and keep a note of that source/version. The small multilingual weight file is approximately 465 MiB; models vary. Do not assume every file named Whisper has the same licence. Weight downloads are optional and never bundled here.

In Pip Capture Settings choose **Speech tool** and **Speech weights**. Advanced language defaults to `auto`. Text/audio saving remains usable when speech files are absent. A file-fed test uses a new output path (never overwrite source audio):

```sh
'build/Capture Replica.app/Contents/MacOS/PipCapture' --transcribe-file sample.wav /absolute/path/whisper-cli /absolute/path/ggml-small.bin /absolute/path/new-result.json
```

Use synthetic speech and inspect words/timestamps. The baseline's own Settings require the same executable/weights configured independently. Baseline optional additional engines are unqualified source paths; the Pip edition uses only whisper.cpp.

A verified example weight is the MIT `ggml-small.bin` conversion from the pinned Hugging Face repository revision below. Size:487601967 bytes (about465MiB). Downloading is optional and only needed for local speech. Verify before choosing it in Settings:

```sh
curl --fail --location 'https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-small.bin' --output ggml-small.bin
printf '%s  %s\n' '1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b' 'ggml-small.bin' | shasum -a 256 -c -
```

This downloads data directly, not a remote installer script. See [conversion repository](https://huggingface.co/ggerganov/whisper.cpp) and [Whisper licence](https://github.com/openai/whisper/blob/main/LICENSE). Do not automatically choose a different weight when a hash fails.

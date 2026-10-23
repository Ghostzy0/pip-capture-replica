# Capture Replica

An experimental original local macOS reconstruction project targeting documented Voicenotes for Mac2.3.7 workflows. **Incomplete reference fidelity; not a completed1:1 clone.** No vendor branding, proprietary source, account service or reference captures are included. No affiliation or endorsement is implied.

This is the canonical Neutral Core reproduction effort. [Pip Capture](https://github.com/Ghostzy0/pip-capture) is the separate custom repository for Neutral Plus, Pip Core and Pip Plus. The source is shared through an exact [commit and file-hash pin](SHARED-CORE.json), rather than four drifting backends. The additional MIT WhisperNotes snapshot is provenance comparison only, not the primary target.

## What works and what remains

The local shared core saves text and retained audio, supports explicit recording controls, batch whisper.cpp transcription, timestamped sources/corrections, exact-word quoted retrieval, tags/folders/favourites, Markdown/audio export and recoverable trash/drafts. The replica has an original Home-first neutral list/detail shell with a red Record action.

Signed-in reference screens and exact geometry remain unobserved. Live transcription, diarisation, system audio, generative Ask/summaries, in-recording contextual notes, global start/stop/cancel shortcuts, team/calendar/sync and mobile are not reproduced. Option+N currently opens recording controls before explicit Start. See [reference scope](docs/REPLICA-SCOPE.md) and [test evidence](TESTING.md). A compile or screenshot is not a fidelity pass.

## Build

Apple Silicon macOS14+, full Xcode selected and Python3 for build validation. No model, account, telemetry or hosted core service is required to build. Models are optional and separately installed.

```sh
git clone https://github.com/Ghostzy0/pip-capture-replica.git
cd pip-capture-replica
python3 scripts/verify-shared-core.py
swift test --jobs 2
./scripts/build-replica.sh
open 'build/Capture Replica.app'
```

The package is ad-hoc signed, not Developer ID signed or notarised. Do not disable Gatekeeper globally. Downloadable binaries are withheld pending final native qualification; source previews state their gaps. [AI setup](docs/AI-SETUP.md) has a short assistant prompt and pinned optional speech instructions.

## Storage and privacy

Bundle ID `com.pipreps.capture.replica`; library `~/Library/Application Support/Capture Replica/`. Preferences and data are separate from the custom variants. No automatic library migration/merge is provided. Quit the app and back up the complete directory, including index/audio/drafts. Local data is plaintext protected by account/filesystem permissions; app-level encryption is absent. Microphone permission is requested only after an explicit recording action. Text/import/export remain usable without it.

## Evidence and help

Shared regression/package evidence is in [TESTING](TESTING.md); [FAQ](docs/FAQ.md), [workflows](docs/WORKFLOWS.md), [provenance](UPSTREAM.md), [notices](THIRD_PARTY_NOTICES.md), [security](SECURITY.md), [contributing](CONTRIBUTING.md) and [change notes](CHANGELOG.md) explain the boundaries. Code is [MIT](LICENSE), maintained by [Ghostzy0](https://github.com/Ghostzy0).

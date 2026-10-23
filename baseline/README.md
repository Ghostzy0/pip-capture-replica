# Capture comparison baseline

Pinned MIT WhisperNotes source at `05d12535863757943a7e243edd2df7cea1d86f84`. This is an upstream-derived comparison edition, not the source of Mem or Voicenotes. Full upstream attribution is retained in LICENSE and Sources/Cvoxtral/LICENSE.

From this directory run `swift test --jobs 2`; from the repository root run `./scripts/build-baseline.sh` and open `build/Capture Baseline.app`. The baseline app stores its library/audio/Markdown separately in Application Support/Pip Capture Baseline. Configure local whisper.cpp/weights independently in its Settings. No models are included and building downloads none.

Differences from the pinned source: package resource verification accepts nested macOS SwiftPM layout; bundle/data/default Markdown/backend/temp paths are isolated; vendor app icon omitted; optional Cohere loader refuses model downloads and remote Python code. Optional Python/Cohere/Voxtral paths remain unqualified comparison source and may need separately reviewed dependencies/weights. The Pip edition does not use those paths.

Original upstream Swift release compile and 127 tests passed on the qualification host. This export's exact checks and native runtime limitations are listed in ../TESTING.md. The baseline is not full feature parity with the Pip edition, and no product affiliation/endorsement is implied.

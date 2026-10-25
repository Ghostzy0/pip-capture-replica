# Foundation and editions

- WhisperNotes baseline revision: 05d12535863757943a7e243edd2df7cea1d86f84, https://github.com/reidemeister94/whisper-notes . Source copied under baseline/ with MIT and Cvoxtral notices. Original unmodified `swift build -c release` passed; `./build.sh` failed a resource-location assertion after compilation. `swift test`: 127 tests, 0 failures. See TESTING for observed host evidence.
- Declared baseline is an upstream-derived comparison edition, not Mem/Voicenotes source. It preserves functional code and tests, isolates app/data identity, corrects packaging and excludes vendor icon/instructions/history.
- Pip edition is original SwiftUI + Foundation/AVFoundation implementation, with a smaller deterministic storage and explicitly configured whisper.cpp path. It does not link Cvoxtral or use the optional Python backend. Its GUI and recording implementation are distinct from upstream; full functional equivalence is not claimed.
- Oats alternate screened at 79c3bbead82ddc9bb901828d51372a8dc2c3dc87, MIT, https://github.com/ariso-ai/oats . No oats code shipped.
- Mem and Voicenotes: documented workflow references; no account-only workflow observation yet. See PARITY.

Both source editions are in the same clean export. Build Pip with `./scripts/build.sh`; baseline with `./scripts/build-baseline.sh`. Test Pip with `swift test`; baseline with `cd baseline && swift test`. Weight files are shared only when explicitly chosen; data ownership remains independent.
85a1c6b18a6b0a06dfe9fd4f6d6a5d4979f74ec861eaef4bc7868b5492b8a117  apps/capture/Resources/Geist-Regular.ttf
c683bfbcc7e087f5d37a54ef628f10387c451a83ddc459b151403a164ac46c90  apps/capture/Resources/Geist-OFL.txt

Baseline hardening: unique recording temp name, all audio/backend/default Markdown paths isolated, and optional Cohere inference refuses network fetch and remote model Python code (`local_files_only=True`, `trust_remote_code=False`). Optional engine installation remains unqualified and is not part of the Pip workflow.

Verified optional local ASR weight available on qualification host: `ggml-small.bin`, 487601967 bytes, SHA256 `1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b`, matched the Hugging Face ggerganov/whisper.cpp LFS index on 23 October. Reused read-only for synthetic tests; no weight redistributed. Intended engine source revision `231638a0717b7822784297e5980965ffcec05810` (official ggml-org/whisper.cpp), not yet built at this checkpoint.

Audit-driven baseline patches (qualification pending): Markdown exports now include stable note IDs, reject dot/path/symlink folder escapes, preserve unknown files and collisions, and use nonrecursive empty-folder deletion. Folder metadata changes only follow successful filesystem work. Recorder temp audio is unique per instance. These are deliberate safety changes to the upstream comparison edition, not claims that upstream shipped them.


## Shared Capture source pin — 25 October 2026

The Replica source candidate vendors the 14 Swift files identified by `SHARED-CORE.json` from the public custom Capture source repository at commit `7aa353b679c64ae87ab41c7c97a4724c8e730d3c`. The manifest records per-file SHA256 values. Existing MIT and upstream notices remain in place; the shared source is vendored locally and is not fetched at runtime. This pin records source provenance only; it does not establish Replica-specific native behavior or reference fidelity.

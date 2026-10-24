# Test evidence

## Current candidate — 24 October 2026

Replica0.1.0-alpha.2 uses the deliberately updated shared-source pin.49 shared tests passed with zero failures/skips, including recovery retry/reopen/source safety and optional metadata compatibility. The shared source and local replica package/configuration/ad-hoc signature checks passed. This does not qualify new native appearance, microphone, full accessibility, signed-in reference workflows or complete fidelity. Previous23October reference/ASR/comparison evidence is retained below for unchanged paths; clean exported-checkout evidence is separate.

23 October2026. Qualification host: Apple Silicon arm64, macOS27.0.1, Swift6.4, full Xcode. Deployment target macOS14; older OS/Intel runtime unverified.

| Check | Executed result | Limits |
| --- | --- | --- |
| Shared storage/model/audio/edition tests |42 passed, zero failures | Synthetic temporary-directory/process fixtures; no microphone |
| Pinned upstream comparison tests |141 tests, one optional real-engine test skipped, zero failures | Additional file-fed engine result recorded separately when run |
| Four app packages |All four built; deep strict ad-hoc signatures verified | Not Developer ID signed/notarised |
| Comparison package |Built; licence notices and ad-hoc signature verified | Optional provenance comparison, not one of the four product variants |
| Earlier native Pip text workflow |Synthetic note create/edit/save, folder/tags, favourite, source quote observed | Precedes latest visible-action/folder/tag fixes and Plus controls |
| Actual microphone record/pause/resume/save |Pending | No grant changed during current qualification |
| Final four-variant native UI/accessibility |Pending | Dark/Oat, minimumwidth, keyboard, reducedmotion and VoiceOver need exact package evidence |
| Real local file-fed speech |Passed direct engine, packaged Pip CLI and comparison test with unchanged source hash |One synthetic voice/11.679s file; microphone/general accuracy separate |
| Clean public checkout |42 shared tests,141 comparison tests(one optional skip), all four and comparison packages passed |Fresh history/export; native acceptance separate |

The42-test suite includes original-audio preservation, corrected/original transcript separation, old-index compatibility, malformed-index preservation, safe atomic storage, concurrent writers, purge rollback/restart, draft recovery, retention/edit races, source-linked recall, worker cancellation/timeout/stale-result rejection, AVFoundation conversion, and safe crash-workspace cleanup. Cleanup preserves live speech children, uncertain launch states, reused/unknown PIDs, unmarked directories and symlinks. Edition tests cover isolated identities and composable Plus filters; Core ignores extras.

The pinned WhisperNotes original compiled in13.59s and passed127 original tests; its original packaging assertion failed on nested SwiftPM resources. The declared comparison repairs packaging and adds containment/collision/mirror-error tests. It preserves original source bytes and licence notices; this is not a claim that the original script passed.

Three independent technical/UI/release reviews found and drove fixes. A later independent Plus source review found active-recording presentation and filter-empty copy issues; final corrected source passed the42-test package checkpoint. Source review is distinct from rendered/native acceptance.

Reference Mem/Voicenotes workflows remain documented rather than account-tested. Official Voicenotes2.3.7 was observed only at Welcome/sign-in; no signup or terms were accepted. Complete competitor equivalence, human transcription accuracy, network isolation tracing, full VoiceOver, macOS14/Intel and stable release readiness remain unverified.

## Pinned speech integration

whisper.cpp231638a0717b7822784297e5980965ffcec05810 and MIT ggml-small.bin SHA2561be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b ran locally with Metal. Same16kHz mono WAV in all three paths; input SHA256ef708e53b4096be5ee2faa90c064fe7fd2a201ff7a37f9695ee9fff99ce01fe2 remained unchanged. Direct and Pip text matched exactly in this fixture; review retained Alice Morgan, negation, £19.50, meeting number2,10:30 and Friday correctly. Pip produced two valid timestamped segments. The optional comparison RealEngineTests also passed when configured with the same files.

| Invocation | Wall seconds | Reported maximum RSS bytes |
| --- | ---: | ---: |
| 05-direct-engine |32.06 |895336448 |
| 06-packaged-pip-cli |20.32 |902447104 |
| 07-baseline-real-engine-test |9.15 |893190144 |

Metrics are raw `/usr/bin/time -l` invocation reports on a shared host. Warmup, concurrency and different thread defaults prevent comparative speed claims. Wrapper CPU time is not a full child/GPU energy measurement. Energy and real microphone resource use remain unmeasured. Child jobs finished and the shared model hash was unchanged.

## Qualification patch2 / separate replica

Final Core0.1.0-alpha.2 and Plus0.2.0-alpha.2 source passed42shared tests. All four packages passed signature verification and their own non-UI configuration diagnostic, checking actual name/bundleID/storage/version/theme/extras flags. The separate Capture Replica0.1.0-alpha.1 also built and passed signature/configuration checks with com.pipreps.capture.replica and its own Capture Replica storage folder. These are executable bundle checks, not native UI acceptance.

The last native slice exercised alpha1 Pip Plus tagfilter, idle recorder collapse and CmdOptionR expansion, and Pip Core tag editing/CmdS save. No microphone started. It exposed selected-row contrast under a purple macOS accent. Patch2 corrects focused/unfocused text colors in source; its final rendered contrast is pending. Computer-use disconnected while opening Settings and failed to reconnect after a reset, so neutral/replica, dark/Oat, minimumwidth and remaining assistive/native workflows remain unverified. Owned apps were stopped and no new grants were requested. Downloadable binary release is withheld pending this UI gate; source remains experimental.

One63-sample Plus navigation segment reported median0% CPU with a43.7% launch/interaction peak and maximum154144KiB RSS. This mixes startup/interaction/idle; it is not a recording/energy benchmark or efficiency claim. Core samples were interrupted and are not reported.

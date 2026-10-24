# Workflow parity and evidence

23 October 2026. Primary recognisable references: Mem Voice Mode and Voicenotes Mac; open-source foundation: WhisperNotes `05d12535863757943a7e243edd2df7cea1d86f84`. Reference account-only workflows remain **documented/unobserved**. Pip source implementation below requires the named runtime evidence before acceptance; code is not proof of execution.

| Workflow | Reference evidence | Upstream comparison | Shared Capture Core / current gap |
|---|---|---|---|
| Voice/text inbox | Mem/Voicenotes official docs | Audio library + editable text | Real native text/audio library implemented; earlier native text/save/recall observed; final matrix UI pending |
| Record/pause/resume/cancel/save | Mem docs pause/resume; Voicenotes docs cancel | Start/stop only | AVAudioRecorder controls implemented; new mic consent + real recording acceptance pending |
| Retain original audio | Mem docs attachment | Copied WAV | Original imported bytes retained; recording AAC retained; byte-preservation regressions pass |
| Edit transcript/source | Mem docs word-for-word transcript | Editable plain text | Editable note plus immutable original/timestamped transcript. Timed corrections now preserve original segments separately; correction/compatibility regressions and four-package build pass |
| Tags/folders/favourites/search | WhisperNotes source; reference docs | Existing SQLite library | Implemented local JSON library; exact source retrieval and no-match state; semantic recall absent |
| Source recall | Mem Chat/Voicenotes Ask docs | Absent | Deterministic matching quotes linked to note/timestamp. Generative/semantic answers are absent |
| Local summaries | Reference proprietary summaries documented | Absent | Extractive highlights labelled as quotes. Generative local summaries deferred pending a licensed tested runtime |
| Import/export | Voicenotes imports web/paid, Mac unavailable per docs | Automatic Markdown sync | Explicit text/audio import and Markdown/original-audio export; no silent personal-folder sync |
| Retention/delete/recovery | Voicenotes Basic visible history documented | Delete confirmation, no trash | Explicit recoverable trash, purge confirmation, retention preview default-off, unfinished draft recovery |
| Offline/missing speech files | Local-only WhisperNotes documented | File path configuration | Local text/audio library independent of speech files; missing-tool/model failure preserves sources |
| Live transcript/speakers | Voicenotes docs | Voxtral optional unqualified | Not implemented; batch timestamps only |
| UI | Voicenotes 2.3.7 Welcome/sign-in observed; signed-in workflows and Mem account screens unobserved | Upstream SwiftUI | Neutral system surfaces/type or Pip Paper light/dark/Oat; earlier Pip render observed, final matrix review pending |

Exact upstream original build/test evidence: release compilation 13.59 s; 127 tests/0 failures. Original build.sh resource assertion failed after compile; baseline export repairs packaging without claiming original script success. Only synthetic app content is eligible for public screenshots. Reference media is not an app asset.

Source documentation: [Mem Voice Mode](https://get.mem.ai/features/voice), [Mem Mac](https://get.mem.ai/download/mac), [Voicenotes Mac](https://help.voicenotes.com/en/articles/11161004-how-to-use-voicenotes-on-mac), [WhisperNotes](https://github.com/reidemeister94/whisper-notes). Documentation is not native observation or demand validation.

Plus (both appearances) adds the same collapsible in-window recorder and selectable library tag filter. These are additions to the declared Core workflow, not reference parity claims. 42 shared tests and all four package builds pass; final native Plus acceptance remains pending.

24 October 2026 candidate: 49 shared tests and all four custom packages plus the separate replica passed local source qualification. Recovery retry identity and retained-source safety have new regressions. The changed recorder and appearance paths still need native acceptance. See [current test evidence](TESTING.md); the 42-test result above is the earlier 23 October snapshot. Clean exported-checkout checks passed as described in TESTING.md; this does not establish native acceptance.

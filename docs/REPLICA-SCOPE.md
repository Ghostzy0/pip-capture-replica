# Capture Replica: reference scope

Capture Replica is a separate experimental original implementation targeting the documented workflows of Voicenotes for Mac2.3.7. It is not a vendor-authored app, an affiliated product or a completed1:1 reproduction. [Capture](https://github.com/Ghostzy0/pip-capture) contains the custom Neutral Plus/Pip Core/Pip Plus work; the separate [replica repository](https://github.com/Ghostzy0/pip-capture-replica) holds the canonical Neutral Core reproduction effort.

## Evidence available

The official Mac2.3.7 build102 was observed at Welcome/sign-in only. Read-only shipped-resource inspection confirmed its bundle/version identity. Official [Mac help](https://help.voicenotes.com/en/articles/11161004-how-to-use-voicenotes-on-mac) documents Home/Meetings, a prominent red Record action, Option+N start/stop, Option+C cancel, live transcripts, questions and notes during recording, Ask Anything and shortcut settings. Public product text documents date/time, title, preview and duration in a library. These documents do not establish exact native screen geometry or every control's behavior.

The current replica uses an original Home-first neutral shell, red Record action, library list/detail and local retained sources. Geometry and navigation details are implementation choices until compared with signed-in native screens. No vendor graphics, proprietary source, service credentials or reference captures are shipped.

## Implemented shared local behavior

Text/audio library, explicit save, original audio retention/playback, batch local whisper.cpp transcription, timed source/corrections, exact-word quoted retrieval, folders/tags/favourites, export, recoverable trash/drafts and opt-in retention preview share the custom app's licensed core. The replica package has its own bundle ID, data directory and preferences. The build opens recording controls before an explicit Start; Option+N does not yet reproduce a global start/stop toggle.

## Material parity gaps

Signed-in Home/Meetings/record/Ask/settings layouts remain unobserved. Live transcription, speaker diarisation, system-audio capture, generative Ask/summaries, in-recording contextual notes, dictation, team/calendar/sync and cross-device workflows are not implemented. Documentation has conflicting speaker-label claims and may describe newer server behavior. Full keyboard shortcuts, timing, failure/recovery and accessibility parity need direct comparison. The local import/export/retention features are original adaptations; official Mac help says imports are unavailable in its documented version.

The included MIT WhisperNotes snapshot is provenance comparison, not the primary target. A shared-core pin and file hashes in the replica repository prevent silently calling an unrelated foundation a faithful recreation. [TESTING](../TESTING.md) lists actual execution; no source review, compile or screenshot alone establishes complete parity.

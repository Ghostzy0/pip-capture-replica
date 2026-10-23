# Capture FAQ

## What does Capture do?

Capture is an experimental macOS voice and text inbox. Save text or original audio, organise notes, find quoted source passages, and export Markdown or audio. Neutral and Pip appearances share one implementation.

## Which variant should I build?

Core provides the declared capture/library workflow. Plus adds a tag filter and collapsible recording controls inside the main window. Both are available with native neutral styling or the Pip Paper/Oat theme. Each has its own app identity and library; see the [variant table](https://github.com/Ghostzy0/pip-capture#four-app-variants).

## Does it need an account or subscription?

The app has no account, telemetry or hosted core service. Local transcription needs a separately installed whisper.cpp executable and compatible weights. The app does not download either automatically. Check their licences and hashes using the [setup guide](AI-SETUP.md).

## Is everything encrypted?

Libraries and recordings are local plaintext protected by the Mac account and filesystem permissions. Capture does not provide app-level encryption. Check where you export files and back up the complete library.

## Can I trust every transcript or answer?

Recognition can mishear names, numbers and negation. Compare important words with the retained audio. Find in sources returns matching quotations; it does not generate semantic answers. Highlights are extracts, not an independent factual summary.

## Can I switch variants without losing my notes?

Variants use separate Application Support folders. No automatic migration or library merge is provided. Keep the original library intact, quit the app, and back up its entire folder before experimenting. Markdown/audio exports are portable copies; a complete cross-variant restore flow is not qualified.

## Which permissions are required?

Microphone access is requested only after Start recording. Text capture, imports and exports remain available without it. Capture does not require Accessibility or Screen Recording permission. Current microphone acceptance limits are in [TESTING](../TESTING.md).

## Is this Mem, Voicenotes or WhisperNotes?

No. Capture is an original implementation with declared workflow references. A separately pinned MIT WhisperNotes comparison is included for reproducibility. [Provenance](../UPSTREAM.md) and [notices](../THIRD_PARTY_NOTICES.md) distinguish the code and references.

## Is this ready for important production recordings?

It is an experimental alpha. See [test evidence](../TESTING.md), [workflow gaps](../PARITY.md) and [security guidance](../SECURITY.md). Ad-hoc builds are not Developer ID signed or notarised. Back up source recordings and verify exports before relying on an alpha.

## Which library does the replica use?

Capture Replica has its own Application Support/Capture Replica directory. It is an incomplete original reproduction effort; see REPLICA-SCOPE.md. It does not automatically copy or merge custom-app data.

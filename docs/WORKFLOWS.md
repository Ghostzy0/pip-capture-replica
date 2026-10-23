# Capture workflows

## Save and find a text note

Choose New note, enter a title and text, then Save changes. Edit the folder and comma-separated tags to organise it. Search matches saved text, titles, tags, folders and transcript sources. Plus can also select a known tag from Filter by tag. Clear filters restores the broader view.

## Keep an original recording

Choose Record, then Start recording. If microphone access is unavailable, use text or import an existing audio file. Pause and resume explicitly; Save recording creates a capture with its original audio. Discard asks for confirmation. Plus can collapse the controls and browse the library while the same session remains active; expand to inspect details. No floating idle recorder is created.

## Transcribe locally

Follow [AI-SETUP](AI-SETUP.md), verify the executable and weights, and select them in Settings. Open a saved audio capture and transcribe it. Keep the original, review the timestamped transcript, then make corrections separately. Missing speech files do not prevent saving notes or original audio.

## Export and recover

Use a capture's More menu to export Markdown or its original audio to a folder you choose. Export files are separate copies. Recently deleted preserves a capture until explicit permanent deletion; Restore returns it. Settings retention is a reviewable preview, off by default, and moves reviewed captures to Recently deleted without timed deletion. Unfinished recording drafts appear for explicit recovery.

## Back up before switching or upgrading

Quit the app and copy its entire Application Support folder from the [variant table](https://github.com/Ghostzy0/pip-capture#four-app-variants), including the index and audio/drafts. Preserve the original backup. No automatic merge or qualified cross-variant migration is provided. A broken or incompatible index blocks writes and keeps its bytes; recover from a known complete backup rather than discarding sources.

These instructions describe implemented workflows. [TESTING](../TESTING.md) states which exact native paths were exercised and which remain unverified.

The replica package uses its own Capture Replica storage folder; Plus controls described above belong to the separate custom variants.

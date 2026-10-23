#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../baseline"
swift build -c release --jobs 2
bundle="../build/Capture Baseline.app"
if [[ -e "$bundle" ]]; then mv "$bundle" "../build/previous-baseline-$(date -u +%Y%m%dT%H%M%SZ).app"; fi
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp .build/release/WhisperNotes "$bundle/Contents/MacOS/WhisperNotes"
cp Info.plist "$bundle/Contents/Info.plist"
# SwiftPM on macOS can nest copied resources in Contents/Resources. Preserve the full bundle.
cp -R .build/release/WhisperNotes_WhisperNotesLib.bundle "$bundle/Contents/Resources/"
test -f "$bundle/Contents/Resources/WhisperNotes_WhisperNotesLib.bundle/Contents/Resources/CohereBackend/cohere_transcribe.py" || test -f "$bundle/Contents/Resources/WhisperNotes_WhisperNotesLib.bundle/CohereBackend/cohere_transcribe.py"
cp LICENSE "$bundle/Contents/Resources/UPSTREAM-LICENSE"
cp Sources/Cvoxtral/LICENSE "$bundle/Contents/Resources/Cvoxtral-LICENSE"
codesign --force --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
printf 'Built upstream-derived baseline: %s\n' "$bundle"

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
requested="${1:-pip-core}"
if [[ $# -gt 1 ]]; then
    printf 'Usage: %s [neutral-core|neutral-plus|pip-core|pip-plus|all]\n' "$0" >&2
    exit 64
fi
case "$requested" in
    neutral-core|neutral-plus|pip-core|pip-plus) editions=("$requested") ;;
    all) editions=(neutral-core neutral-plus pip-core pip-plus) ;;
    *) printf 'Unknown edition: %s\n' "$requested" >&2; exit 64 ;;
esac

# All editions share one cached implementation; bundle metadata selects the edition.
swift build -c release --jobs 2
binary_directory="$(swift build -c release --show-bin-path)"
mkdir -p build/AppIcon.iconset
swift scripts/icon.swift build/AppIcon.iconset/icon_512x512@2x.png
for size in 16 32 128 256 512; do sips -z "$size" "$size" build/AppIcon.iconset/icon_512x512@2x.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null; done
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
stage=""
cleanup() { if [[ -n "$stage" && -d "$stage" ]]; then rm -rf -- "$stage"; fi; }
trap cleanup EXIT
for edition in "${editions[@]}"; do
    case "$edition" in
        neutral-core) name="Capture Neutral Core"; identifier="com.pipreps.capture.neutral.core"; version="0.1.0-alpha.2"; build_number=1 ;;
        neutral-plus) name="Capture Neutral Plus"; identifier="com.pipreps.capture.neutral.plus"; version="0.2.0-alpha.2"; build_number=2 ;;
        pip-core) name="Pip Capture"; identifier="com.pipreps.capture"; version="0.1.0-alpha.2"; build_number=1 ;;
        pip-plus) name="Pip Capture Plus"; identifier="com.pipreps.capture.plus"; version="0.2.0-alpha.2"; build_number=2 ;;
    esac
    stage="$(mktemp -d build/.package-XXXXXX)"
    candidate="$stage/$name.app"
    bundle="build/$name.app"
    mkdir -p "$candidate/Contents/MacOS" "$candidate/Contents/Resources"
    cp "$binary_directory/PipCapture" "$candidate/Contents/MacOS/"
    cp Resources/Info.plist "$candidate/Contents/Info.plist"
    plist="$candidate/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName $name" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $name" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $identifier" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$plist"
    /usr/libexec/PlistBuddy -c "Set :NSMicrophoneUsageDescription $name records audio only when you choose Start recording. Audio stays on your Mac." "$plist"
    for key in PipCaptureEdition PipCaptureStorageName; do
        if /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null 2>&1; then
            /usr/libexec/PlistBuddy -c "Delete :$key" "$plist"
        fi
    done
    /usr/libexec/PlistBuddy -c "Add :PipCaptureEdition string $edition" "$plist"
    /usr/libexec/PlistBuddy -c "Add :PipCaptureStorageName string $name" "$plist"
    cp Resources/*.ttf Resources/*OFL.txt "$candidate/Contents/Resources/"
    cp build/AppIcon.icns "$candidate/Contents/Resources/"
    cp LICENSE THIRD_PARTY_NOTICES.md "$candidate/Contents/Resources/"
    cp baseline/LICENSE "$candidate/Contents/Resources/WhisperNotes-LICENSE"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :PipCaptureEdition' "$plist")" == "$edition" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" == "$identifier" ]]
    codesign --force --sign - "$candidate"
    codesign --verify --deep --strict "$candidate"
    python3 scripts/verify-configuration.py "$candidate" "$edition" "$name" "$identifier" "$version"
    # Keep the last verified bundle intact until its replacement also verifies.
    if [[ -e "$bundle" ]]; then mv "$bundle" "build/previous-$edition-$(date -u +%Y%m%dT%H%M%SZ)-$$.app"; fi
    mv "$candidate" "$bundle"
    rmdir "$stage"; stage=""
    printf 'Built ad-hoc signed %s (%s): %s\n' "$edition" "$version" "$bundle"
done

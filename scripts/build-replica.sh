#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/verify-shared-core.py
./scripts/build.sh neutral-core
name='Capture Replica'
stage="$(mktemp -d build/.replica-XXXXXX)"
trap 'rm -rf -- "$stage"' EXIT
cp -R 'build/Capture Neutral Core.app' "$stage/$name.app"
plist="$stage/$name.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Capture Replica' "$plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Capture Replica' "$plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.pipreps.capture.replica' "$plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 2' "$plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.1.0-alpha.2' "$plist"
/usr/libexec/PlistBuddy -c 'Set :PipCaptureStorageName Capture Replica' "$plist"
/usr/libexec/PlistBuddy -c 'Set :NSMicrophoneUsageDescription Capture Replica records audio only after Start recording. Original audio stays on this Mac.' "$plist"
/usr/libexec/PlistBuddy -c 'Add :PipCaptureReplica bool true' "$plist"
codesign --force --sign - "$stage/$name.app"
codesign --verify --deep --strict "$stage/$name.app"
python3 scripts/verify-configuration.py "$stage/$name.app" neutral-core "$name" com.pipreps.capture.replica 0.1.0-alpha.2 replica
if [[ -e "build/$name.app" ]]; then mv "build/$name.app" "build/previous-replica-$(date -u +%Y%m%dT%H%M%SZ)-$$.app"; fi
mv "$stage/$name.app" "build/$name.app"
printf 'Built experimental source-limited replica: build/%s.app\n' "$name"

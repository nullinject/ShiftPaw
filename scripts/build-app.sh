#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_VERSION="${APP_VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_DIR/.build/app}"
APP_BUNDLE="$OUTPUT_DIR/ShiftPaw.app"

if [[ -n "${SWIFT_EXECUTABLE:-}" ]]; then
    EXECUTABLE_PATH="$SWIFT_EXECUTABLE"
else
    swift build --package-path "$PROJECT_DIR" --configuration "$CONFIGURATION" --product ShiftPaw
    BIN_DIR="$(swift build --package-path "$PROJECT_DIR" --configuration "$CONFIGURATION" --show-bin-path)"
    EXECUTABLE_PATH="$BIN_DIR/ShiftPaw"
fi

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
    printf 'Executable not found or not executable: %s\n' "$EXECUTABLE_PATH" >&2
    exit 1
fi

rm -rf "$APP_BUNDLE"
install -d "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
install -m 755 "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/ShiftPaw"
install -m 644 "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
install -m 644 "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
else
    codesign --force --sign - "$APP_BUNDLE"
fi

codesign --verify --deep --strict "$APP_BUNDLE"
printf '%s\n' "$APP_BUNDLE"

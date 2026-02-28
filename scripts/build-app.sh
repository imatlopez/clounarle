#!/bin/bash
# Build TherapyJournal as a proper macOS .app bundle
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="Therapy Journal"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"

echo "Building TherapyJournal..."
cd "$PROJECT_DIR"
swift build 2>&1

echo "Creating app bundle at $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/debug/TherapyJournal" "$APP_BUNDLE/Contents/MacOS/TherapyJournal"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy resources
cp "$PROJECT_DIR/Resources/JournalingSystemPrompt.txt" "$APP_BUNDLE/Contents/Resources/"

echo "App bundle created: $APP_BUNDLE"
echo ""
echo "To run:  open \"$APP_BUNDLE\""
echo "To kill: pkill -f 'Therapy Journal' || true"

#!/usr/bin/env bash
# Build TherapyJournal and package it as a proper .app bundle.
# Run from the repo root: ./scripts/build-app.sh

set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO/.build/Therapy Journal.app"
CONTENTS="$APP/Contents"

echo "→ Building..."
swift build --package-path "$REPO" 2>&1

echo "→ Packaging .app bundle..."
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

# Binary
cp "$REPO/.build/debug/TherapyJournal" "$CONTENTS/MacOS/TherapyJournal"

# Info.plist (always sync from source)
cp "$REPO/Resources/Info.plist" "$CONTENTS/Info.plist"

# Resources
cp "$REPO/Resources/JournalingSystemPrompt.txt" "$CONTENTS/Resources/JournalingSystemPrompt.txt"

echo "→ Relaunching..."
pkill -x TherapyJournal 2>/dev/null || true
sleep 0.5
open "$APP"

echo "✓ Done — Therapy Journal launched as .app"

#!/usr/bin/env bash
# Captures every screen in screenshot mode into docs/screenshots/<lang>/<appearance>/<scene>.png.
# Build the app first with ./scripts/build-app.sh.
#
# Usage: screenshots.sh [languages] [appearances] [scenes]
#   e.g. screenshots.sh "en tr" "dark light" "welcome general menu"
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/TidyDock.app/Contents/MacOS/TidyDock"
LANGS="${1:-en tr}"
APPEARANCES="${2:-dark light}"
SCENES="${3:-welcome permission setup general apps shortcuts about notice suggestion menu}"

[[ -x "$APP" ]] || { echo "Build the app first: ./scripts/build-app.sh" >&2; exit 1; }

FIND="$ROOT/build/find-window"
swiftc -O "$ROOT/scripts/find-window.swift" -o "$FIND"

for lang in $LANGS; do
    for appearance in $APPEARANCES; do
        out="$ROOT/docs/screenshots/$lang/$appearance"
        mkdir -p "$out"
        for scene in $SCENES; do
            TIDYDOCK_SCREENSHOT="$scene" TIDYDOCK_APPEARANCE="$appearance" "$APP" -AppleLanguages "($lang)" >/dev/null 2>&1 &
            pid=$!
            sleep 2.5
            if id="$("$FIND" "$pid")"; then
                screencapture -x -l"$id" "$out/$scene.png"
                echo "✓ $lang/$appearance/$scene"
            else
                echo "✗ $lang/$appearance/$scene: no window" >&2
            fi
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        done
    done
done

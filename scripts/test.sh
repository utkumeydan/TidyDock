#!/usr/bin/env bash
# Runs the unit tests. With only the Command Line Tools installed, SwiftPM
# sometimes fails to load the swift-testing macro plugin, so pass its path.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
extra=()
[[ -d "$PLUGINS" ]] && extra=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS")
swift test --package-path "$ROOT" "${extra[@]}" "$@"

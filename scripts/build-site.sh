#!/usr/bin/env bash
# Assembles the GitHub Pages site into _site/ (the page plus images from docs/).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/_site"
rm -rf "$OUT"
mkdir -p "$OUT/assets"
cp "$ROOT/site/index.html" "$OUT/"
cp "$ROOT/docs/icon.png" "$ROOT"/docs/demo-*.gif "$OUT/assets/"
cp -R "$ROOT/docs/screenshots" "$OUT/assets/"
[[ -f "$ROOT/docs/og.png" ]] && cp "$ROOT/docs/og.png" "$OUT/assets/"
echo "✓ $OUT"

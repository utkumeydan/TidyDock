#!/usr/bin/env bash
# Lists strings used in the code that a translation is missing, and stale ones it still has.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
used="$(mktemp)"
grep -rhoE 'L\("([^"\\]|\\.)*"' "$ROOT/Sources/TidyDock" | sed -E 's/^L\(//' | sort -u > "$used"
status=0
for file in "$ROOT"/Support/Localization/*.lproj/Localizable.strings; do
    lang="$(basename "$(dirname "$file")" .lproj)"
    [[ "$lang" == en ]] && continue
    have="$(grep -oE '^"([^"\\]|\\.)*"' "$file" | sort -u)"
    missing="$(comm -23 "$used" <(echo "$have"))"
    stale="$(comm -13 "$used" <(echo "$have"))"
    if [[ -n "$missing$stale" ]]; then
        status=1
        echo "── $lang"
        [[ -n "$missing" ]] && echo "$missing" | sed 's/^/  missing: /'
        [[ -n "$stale" ]] && echo "$stale" | sed 's/^/  stale:   /'
    fi
done
rm -f "$used"
[[ $status == 0 ]] && echo "✓ All translations are complete"
exit $status

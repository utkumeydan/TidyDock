#!/usr/bin/env bash
# Builds build/TidyDock.app (and a zip for releases).
#
# Environment:
#   VERSION             marketing version, default 0.1.1
#   BUILD               build number, default: git commit count
#   ARCHS               "arm64", "x86_64" or "arm64 x86_64" for a universal app, default: this Mac
#   SIGN_IDENTITY       codesign identity. Defaults to a "TidyDock Development" certificate
#                       when one is in the keychain, otherwise "-" (ad-hoc). Use the same
#                       certificate for every build so the Accessibility permission survives updates.
#   SPARKLE_PUBLIC_KEY  EdDSA public key; defaults to the TidyDock release key
#   ZIP=1               also write build/TidyDock-<version>.zip
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.1.1}"
BUILD="${BUILD:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
ARCHS="${ARCHS:-$(uname -m)}"
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -q '"TidyDock Development"'; then
        SIGN_IDENTITY="TidyDock Development"
    else
        SIGN_IDENTITY="-"
    fi
fi
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-DNupfV9O2stiVg7dqzqvj2K82/szsL5p5DshB/k3AMg=}"

OUT="$ROOT/build"
APP="$OUT/TidyDock.app"

# Build each architecture on its own (a multi-arch `swift build` trips over
# duplicate outputs) and merge the executables with lipo.
binaries=()
for arch in $ARCHS; do
    echo "→ Compiling ($arch)"
    scratch="$ROOT/.build/$arch"
    swift build -c release --package-path "$ROOT" --arch "$arch" --scratch-path "$scratch"
    BIN="$(swift build -c release --package-path "$ROOT" --arch "$arch" --scratch-path "$scratch" --show-bin-path)"
    binaries+=("$BIN/TidyDock")
done

echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/TidyDock"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/TidyDock"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp -R "$ROOT/Support/Localization/"*.lproj "$APP/Contents/Resources/"

sed -e "s/__VERSION__/$VERSION/" \
    -e "s/__BUILD__/$BUILD/" \
    -e "s|__SPARKLE_PUBLIC_KEY__|$SPARKLE_PUBLIC_KEY|" \
    "$ROOT/Support/Info.plist" > "$APP/Contents/Info.plist"

if [[ -f "$ROOT/Support/AppIcon.icns" ]]; then
    cp "$ROOT/Support/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
fi

echo "→ Signing with identity: $SIGN_IDENTITY"
sign_flags=(--force --sign "$SIGN_IDENTITY")
# Hardened runtime is required for notarization, which only Developer ID certificates can do.
if [[ "$SIGN_IDENTITY" == Developer\ ID* ]]; then
    sign_flags+=(--options runtime --timestamp)
fi
# Sign Sparkle's helpers from the inside out, then the app itself.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for helper in "$SPARKLE/XPCServices/"*.xpc "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app"; do
    [[ -e "$helper" ]] && codesign "${sign_flags[@]}" "$helper"
done
codesign "${sign_flags[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
codesign "${sign_flags[@]}" "$APP"
codesign --verify --strict --verbose=1 "$APP"

if [[ "${ZIP:-0}" == 1 ]]; then
    ZIP_PATH="$OUT/TidyDock-$VERSION.zip"
    rm -f "$ZIP_PATH"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP_PATH"
    echo "→ Wrote $ZIP_PATH"
fi

echo "✓ $APP"

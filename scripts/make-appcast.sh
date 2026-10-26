#!/usr/bin/env bash
# Writes a Sparkle appcast with one item for the given release zip.
#
# Usage: make-appcast.sh <zip> <version> <build> <download-url> <ed-signature> <length> > appcast.xml
set -euo pipefail

ZIP="$1" VERSION="$2" BUILD="$3" URL="$4" SIGNATURE="$5" LENGTH="$6"
[[ -f "$ZIP" ]] || { echo "No such file: $ZIP" >&2; exit 1; }

cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>TidyDock</title>
    <link>https://github.com/utkumeydan/TidyDock</link>
    <item>
      <title>TidyDock $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/utkumeydan/TidyDock/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="$URL" length="$LENGTH" type="application/octet-stream" sparkle:edSignature="$SIGNATURE"/>
    </item>
  </channel>
</rss>
EOF

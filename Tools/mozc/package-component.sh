#!/bin/bash
# Package build/mozc-out as a Mozc component NRIME downloads (MozcUpdater):
#   build/mozc-component/nrime-mozc.zip   libnrime_mozc.dylib, mozc.data, manifest.json
#   build/mozc-component/TAG              mozc-<abi>-<yyyymmdd>-<commit7>, the release tag
#   build/mozc-component/TITLE            "Mozc <version> (<date>)"
# manifest.json carries the C API version, the Mozc commit/date/version and the
# SHA-256 of each file; NRIME checks all of them before using a download.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/mozc-out"
DEST="$ROOT/build/mozc-component"

read -r COMMIT DATE VERSION < "$OUT/MOZC_VERSION"
ABI="$(awk '/^#define NRIME_MOZC_ABI_VERSION/ {print $3}' "$ROOT/Tools/mozc/nrime/nrime_mozc.h")"
[ -n "$ABI" ] || { echo "ERROR: NRIME_MOZC_ABI_VERSION not found"; exit 1; }

rm -rf "$DEST"
mkdir -p "$DEST/stage"
cp "$OUT/lib/libnrime_mozc.dylib" "$OUT/data/mozc.data" "$DEST/stage/"
LIB_SHA="$(shasum -a 256 "$DEST/stage/libnrime_mozc.dylib" | cut -d' ' -f1)"
DATA_SHA="$(shasum -a 256 "$DEST/stage/mozc.data" | cut -d' ' -f1)"
cat > "$DEST/stage/manifest.json" <<JSON
{"abi": $ABI, "commit": "$COMMIT", "date": "$DATE", "version": "$VERSION",
 "files": {"libnrime_mozc.dylib": "$LIB_SHA", "mozc.data": "$DATA_SHA"}}
JSON
ditto -c -k --norsrc --noextattr "$DEST/stage" "$DEST/nrime-mozc.zip"
rm -rf "$DEST/stage"

echo "mozc-$ABI-${DATE//-/}-${COMMIT:0:7}" > "$DEST/TAG"
echo "Mozc $VERSION ($DATE)" > "$DEST/TITLE"
echo "$(cat "$DEST/TAG"): $(cat "$DEST/TITLE") → $DEST/nrime-mozc.zip ($(du -h "$DEST/nrime-mozc.zip" | cut -f1))"

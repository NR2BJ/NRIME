#!/bin/bash
# Build Mozc (Google's Japanese conversion engine) for NRIME → build/mozc-out/
#   lib/libnrime_mozc.dylib  the engine NRIME loads: Mozc, its dependencies, NRIME's C API
#   include/nrime_mozc.h     that C API
#   data/mozc.data           the dictionary data that goes with it
#   MOZC_VERSION             "<commit> <commit date> <Mozc version>"
#
# MOZC_COMMIT in the environment overrides the pin (the component workflow
# builds upstream's latest commit this way).
#
# - The commit is pinned in Tools/mozc/MOZC_COMMIT. Tools/mozc/update.sh moves
#   it to the latest upstream commit (release.sh does that for every beta).
# - Mozc's source lives in build/mozc: git-ignored, and outside Syncthing
#   (~/Documents syncs everything except folders named build).
# - Needs bazelisk (brew install bazelisk); Mozc pins the Bazel version itself.
#   The first build downloads dependencies and takes a few minutes; after that
#   only what changed is rebuilt, and an up-to-date tree takes seconds.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMMIT="${MOZC_COMMIT:-$(tr -d '[:space:]' < "$ROOT/Tools/mozc/MOZC_COMMIT")}"
SRC="$ROOT/build/mozc"
OUT="$ROOT/build/mozc-out"

command -v bazelisk >/dev/null 2>&1 || { echo "ERROR: bazelisk not found — brew install bazelisk"; exit 1; }

if [ ! -d "$SRC/.git" ]; then
    git clone -q --depth 1 https://github.com/google/mozc.git "$SRC"
fi
if [ "$(git -C "$SRC" rev-parse HEAD)" != "$COMMIT" ]; then
    git -C "$SRC" fetch -q --depth 1 origin "$COMMIT"
    git -C "$SRC" checkout -q --detach "$COMMIT"
fi
rsync -a --delete "$ROOT/Tools/mozc/nrime/" "$SRC/src/nrime/"

cd "$SRC/src"
# Mozc limits who may use the session handler; check nothing rather than patch
# its source. Same minimum macOS as the app (otherwise this Mac's version).
FLAGS=(--config oss_macos --config release_build --nocheck_visibility --macos_minimum_os=13.0)
# Extra Bazel flags, e.g. --disk_cache for the component workflow.
if [ -n "${MOZC_BAZEL_FLAGS:-}" ]; then
    read -r -a EXTRA <<< "$MOZC_BAZEL_FLAGS"
    FLAGS+=("${EXTRA[@]}")
fi
bazelisk build "${FLAGS[@]}" //nrime:libnrime_mozc.dylib //data_manager/oss:mozc.data
BIN="$(bazelisk info "${FLAGS[@]}" bazel-bin 2>/dev/null)"

rm -rf "$OUT/lib"
mkdir -p "$OUT/lib" "$OUT/include" "$OUT/data"
cp -f "$BIN/nrime/libnrime_mozc.dylib" "$OUT/lib/libnrime_mozc.dylib"
cp -f "$ROOT/Tools/mozc/nrime/nrime_mozc.h" "$OUT/include/"
cp -f "$BIN/data_manager/oss/mozc.data" "$OUT/data/"
chmod u+w "$OUT"/lib/* "$OUT"/include/* "$OUT"/data/*

VERSION="$(awk -F' = ' '/^MAJOR/{a=$2} /^MINOR/{b=$2} /^BUILD_OSS/{c=$2} /^REVISION/{d=$2} END{printf "%s.%s.%s.%d", a, b, c, d + 1}' version.bzl)"
DATE="$(git -C "$SRC" show -s --format=%cs HEAD)"
echo "$COMMIT $DATE $VERSION" > "$OUT/MOZC_VERSION"
echo "Mozc $VERSION ($COMMIT, $DATE) → $OUT"

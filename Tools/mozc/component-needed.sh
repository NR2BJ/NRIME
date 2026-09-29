#!/bin/bash
# Should the component workflow build a new Mozc component? Prints, for
# $GITHUB_OUTPUT: commit=<upstream master SHA>, build=true|false, reason=<why>.
#
# A new component is built when upstream Mozc changed its version (src/version.bzl)
# or its data (src/data/, which becomes mozc.data) since the newest published
# component — not for every commit, most of which touch other platforms, tests
# or tooling. Also built when none exists yet, or when forced.
#
# Usage: component-needed.sh [force]   (GITHUB_REPOSITORY and GH_TOKEN from the workflow)
set -euo pipefail
FORCE="${1:-false}"
REPO="${GITHUB_REPOSITORY:-NR2BJ/NRIME}"

LATEST="$(git ls-remote https://github.com/google/mozc.git refs/heads/master | cut -f1)"
[ -n "$LATEST" ] || { echo "ERROR: could not read upstream Mozc" >&2; exit 1; }
echo "commit=$LATEST"

LAST_TAG="$(gh release list --repo "$REPO" --limit 100 --json tagName,createdAt \
    --jq '[.[] | select(.tagName | startswith("mozc-"))] | sort_by(.createdAt) | reverse | .[0].tagName // ""')"
if [ "$FORCE" = "true" ]; then
    echo "build=true"; echo "reason=forced"; exit 0
fi
if [ -z "$LAST_TAG" ]; then
    echo "build=true"; echo "reason=no component published yet"; exit 0
fi
LAST_SHA="${LAST_TAG##*-}"
if [ "${LATEST:0:${#LAST_SHA}}" = "$LAST_SHA" ]; then
    echo "build=false"; echo "reason=$LAST_TAG is upstream master"; exit 0
fi

FILES="$(gh api "repos/google/mozc/compare/$LAST_SHA...$LATEST" --jq '.files[].filename')"
COUNT="$(printf '%s\n' "$FILES" | grep -c . || true)"
RELEVANT="$(printf '%s\n' "$FILES" | grep -E '^src/version\.bzl$|^src/data/' | grep -v '^src/data/test/' || true)"
if [ -n "$RELEVANT" ]; then
    echo "build=true"; echo "reason=version or data changed since $LAST_TAG"
elif [ "$COUNT" -ge 300 ]; then
    # The compare API lists at most 300 files: unknown, so build.
    echo "build=true"; echo "reason=too many changes since $LAST_TAG to tell"
else
    echo "build=false"; echo "reason=only code outside version and data changed since $LAST_TAG"
fi

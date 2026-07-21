#!/bin/bash
# Build NRIME and publish it as a GitHub release.
#
# Usage:
#   bash Tools/release.sh 1.0.9            # stable release  → v1.0.9
#   bash Tools/release.sh 1.0.9-beta.1     # test build      → v1.0.9-beta.1 (prerelease)
#   bash Tools/release.sh 1.0.9 --notes-file NOTES.md
#   bash Tools/release.sh 1.0.9 --yes      # skip the confirmation prompt
#
# The channel is derived from the version string: anything containing a "-"
# suffix is published as a GitHub prerelease, which keeps it out of
# /releases/latest and therefore out of the stable in-app update channel.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
REPO="NR2BJ/NRIME"

VERSION=""
NOTES_FILE=""
ASSUME_YES=0

# ---- Parse arguments -------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        --notes-file)
            NOTES_FILE="${2:-}"
            [ -n "$NOTES_FILE" ] || { echo "ERROR: --notes-file needs a path"; exit 1; }
            shift 2
            ;;
        --yes|-y)
            ASSUME_YES=1
            shift
            ;;
        -*)
            echo "ERROR: unknown option: $1"
            exit 1
            ;;
        *)
            [ -z "$VERSION" ] || { echo "ERROR: version specified twice ($VERSION, $1)"; exit 1; }
            VERSION="$1"
            shift
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    echo "Usage: bash Tools/release.sh <version> [--notes-file FILE] [--yes]"
    echo "  stable: 1.0.9        beta: 1.0.9-beta.1"
    exit 1
fi

# Strip a leading "v" so both "1.0.9" and "v1.0.9" work.
VERSION="${VERSION#v}"

# X.Y.Z, optionally followed by a prerelease suffix such as -beta.1
if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'; then
    echo "ERROR: invalid version '$VERSION'"
    echo "       expected 1.0.9 or 1.0.9-beta.1"
    exit 1
fi

case "$VERSION" in
    *-*) IS_PRERELEASE=1; CHANNEL="beta (prerelease)" ;;
    *)   IS_PRERELEASE=0; CHANNEL="stable" ;;
esac

TAG="v$VERSION"

echo "=== NRIME Release ==="
echo "  Version: $VERSION"
echo "  Tag:     $TAG"
echo "  Channel: $CHANNEL"
echo

# ---- Preflight checks ------------------------------------------------------

command -v gh >/dev/null 2>&1 || { echo "ERROR: gh CLI not found"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh is not authenticated (run: gh auth login)"; exit 1; }

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "ERROR: release $TAG already exists on $REPO"
    echo "       bump the version, or delete it first: gh release delete $TAG --repo $REPO"
    exit 1
fi

if [ -n "$NOTES_FILE" ] && [ ! -f "$NOTES_FILE" ]; then
    echo "ERROR: notes file not found: $NOTES_FILE"
    exit 1
fi

# Releases are cut from what is on the remote, so refuse to publish
# a build whose source has not been pushed.
cd "$PROJECT_DIR"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "ERROR: working tree has uncommitted changes — commit them first."
    git status --short --untracked-files=no
    exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
git fetch --quiet origin "$BRANCH" 2>/dev/null || true
if [ -n "$(git log --oneline "origin/$BRANCH..HEAD" 2>/dev/null)" ]; then
    echo "ERROR: local commits are not pushed to origin/$BRANCH — push them first."
    exit 1
fi

# ---- Confirmation ----------------------------------------------------------

if [ "$ASSUME_YES" -ne 1 ]; then
    if [ "$IS_PRERELEASE" -eq 1 ]; then
        echo "This publishes a PRERELEASE. Only users on the beta channel receive it."
    else
        echo "This publishes a STABLE release to every user."
    fi
    printf "Continue? [y/N] "
    read -r REPLY
    case "$REPLY" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "Aborted."; exit 1 ;;
    esac
fi

# ---- Set version and build -------------------------------------------------

CURRENT_BUILD="$(grep -E '^\s+CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed -E 's/.*"([0-9]+)".*/\1/')"
NEXT_BUILD=$((CURRENT_BUILD + 1))

echo
echo "Setting MARKETING_VERSION=$VERSION, CURRENT_PROJECT_VERSION=$NEXT_BUILD"
/usr/bin/sed -i '' -E \
    -e "s/^([[:space:]]+MARKETING_VERSION:).*/\1 \"$VERSION\"/" \
    -e "s/^([[:space:]]+CURRENT_PROJECT_VERSION:).*/\1 \"$NEXT_BUILD\"/" \
    project.yml

echo "Building PKG..."
bash "$PROJECT_DIR/Tools/build_pkg.sh"

PKG_PATH="$BUILD_DIR/NRIME-$VERSION.pkg"
if [ ! -f "$PKG_PATH" ]; then
    echo "ERROR: expected installer not found: $PKG_PATH"
    exit 1
fi
echo "Built: $PKG_PATH ($(du -h "$PKG_PATH" | cut -f1))"

# ---- Commit the version bump ----------------------------------------------

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    git add project.yml
    git commit -q -m "Bump version to $VERSION"
    git push -q origin "$BRANCH"
    echo "Pushed version bump to origin/$BRANCH"
fi

# ---- Publish ---------------------------------------------------------------

RELEASE_ARGS=(
    "$TAG"
    "$PKG_PATH"
    --repo "$REPO"
    --title "$TAG"
    --target "$(git rev-parse HEAD)"
)

if [ "$IS_PRERELEASE" -eq 1 ]; then
    RELEASE_ARGS+=(--prerelease)
fi

if [ -n "$NOTES_FILE" ]; then
    RELEASE_ARGS+=(--notes-file "$NOTES_FILE")
else
    RELEASE_ARGS+=(--generate-notes)
fi

echo "Creating GitHub release..."
gh release create "${RELEASE_ARGS[@]}"

echo
echo "=== Done ==="
echo "  $TAG published to $REPO ($CHANNEL)"
if [ "$IS_PRERELEASE" -eq 1 ]; then
    echo "  Stable users are unaffected; beta-channel users see it on next check."
else
    echo "  All users see it on their next update check."
fi

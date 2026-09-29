#!/bin/bash
# Move NRIME's Mozc to the latest upstream commit (or the one given), rebuild
# it, and run the full test suite against it. On any failure the previous pin
# is restored and rebuilt, so build/mozc-out always matches Tools/mozc/MOZC_COMMIT.
#
# Usage: bash Tools/mozc/update.sh [<commit>]
#
# Does not commit: release.sh commits the new pin when it runs this for a beta;
# run by hand, review and commit Tools/mozc/MOZC_COMMIT yourself.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PIN="$ROOT/Tools/mozc/MOZC_COMMIT"
OLD="$(tr -d '[:space:]' < "$PIN")"
NEW="${1:-$(git ls-remote https://github.com/google/mozc.git refs/heads/master | cut -f1)}"
[ -n "$NEW" ] || { echo "ERROR: could not read the latest Mozc commit"; exit 1; }

if [ "$OLD" = "$NEW" ]; then
    echo "Mozc is up to date ($OLD)."
    bash "$ROOT/Tools/mozc/build.sh"
    exit 0
fi

AHEAD="$(gh api "repos/google/mozc/compare/$OLD...$NEW" --jq '.ahead_by' 2>/dev/null || echo "?")"
echo "Updating Mozc: $OLD → $NEW ($AHEAD commits)"

restore() {
    echo "$1 — restoring $OLD."
    echo "$OLD" > "$PIN"
    bash "$ROOT/Tools/mozc/build.sh" >/dev/null || echo "WARNING: rebuilding $OLD failed too"
    exit 1
}

echo "$NEW" > "$PIN"
bash "$ROOT/Tools/mozc/build.sh" || restore "Mozc $NEW failed to build"

# The suite includes conversions through the real engine (MozcEmbeddedTests).
xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT" >/dev/null
TEST_LOG="$ROOT/build/mozc-update-test.log"
if ! xcodebuild -project "$ROOT/NRIME.xcodeproj" -scheme NRIME -configuration Debug test \
        SYMROOT="$ROOT/build/mozc-update-test" > "$TEST_LOG" 2>&1; then
    grep -E "error:|failed \(" "$TEST_LOG" | head -20 || true
    restore "Tests failed with Mozc $NEW (log: $TEST_LOG)"
fi

echo "Mozc updated to $(cat "$ROOT/build/mozc-out/MOZC_VERSION") — tests passed."

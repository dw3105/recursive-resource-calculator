#!/bin/sh
# Build labelled test zips for one tagged commit, from the committed tree only.
# Usage: build_test_zip.sh <tag-or-sha> <2.0 version> <2.1 version> [output-dir]
set -eu

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    echo "usage: build_test_zip.sh <tag-or-sha> <2.0 version> <2.1 version> [output-dir]" >&2
    exit 2
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
R=${RRC_REPO:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}
OUT=${RRC_TEST_ZIP_DIR:-${4:-$(pwd)}}
SHA=$(git -C "$R" rev-parse "$1")
V20=$2
V21=$3
WORK=$(mktemp -d "${TMPDIR:-/tmp}/rrc-test-zip.XXXXXX")
cleanup() {
    rm -rf "$WORK"
}
trap cleanup 0 1 2 15

mkdir -p "$OUT"
git -C "$R" archive "$SHA" | tar -x -C "$WORK"
cd "$WORK"

build_one() {
    version=$1
    branch=$2
    RRC_CANDIDATE_SHA="$SHA" bash ./generate_release.sh "$version" "$branch"
    archive="$OUT/RRC-Fork_${version}_factorio-${branch}-test.zip"
    python3 -m zipfile -c "$archive" "RRC-Fork_${version}"
    printf 'TEST BUILD: %s  %s  (Factorio %s)\n' \
        "$(sha256sum "$archive" | cut -d' ' -f1)" "$archive" "$branch"
}

build_one "$V20" 2.0
build_one "$V21" 2.1
echo "TEST BUILD: built from $SHA; these archives are not release artifacts"

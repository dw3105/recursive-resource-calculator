#!/bin/sh
# Build the round 8 test zips for one tagged commit, from the committed tree only.
# Usage: build_zip1.sh <tag-or-sha> <2.0 version> <2.1 version>
set -e
R=/home/dev_zaigraev_gmail_com/recursive-resource-calculator
SHA=$(git -C "$R" rev-parse "$1")
V20=$2; V21=$3
WORK=$(mktemp -d)
cd "$WORK"
git -C "$R" archive "$SHA" | tar -x
for pair in "$V20 2.0" "$V21 2.1"; do
  set -- $pair
  RRC_CANDIDATE_SHA="$SHA" bash ./generate_release.sh "$1" "$2"
  python3 -m zipfile -c "RRC-Fork_$1.zip" "RRC-Fork_$1"
  cp "RRC-Fork_$1.zip" /home/dev_zaigraev_gmail_com/share/
  printf '%s  RRC-Fork_%s.zip  (Factorio %s)\n' "$(sha256sum "RRC-Fork_$1.zip" | cut -d' ' -f1)" "$1" "$2"
done
echo "built from $SHA"
echo "entries in the 2.0 zip: $(python3 -c "import zipfile;print(len(zipfile.ZipFile('RRC-Fork_$V20.zip').namelist()))")"
rm -rf "$WORK"

#!/bin/bash
# Usage: generate_release.sh <mod version> <factorio version>
# The output is a package directory.  It is intentionally created beside the
# caller's temporary archive, never in the source checkout.
set -euo pipefail

if [[ $# -ne 2 || -z "$1" || ( "$2" != "2.0" && "$2" != "2.1" ) ]]; then
    echo "usage: generate_release.sh <mod version> <2.0|2.1>" >&2
    exit 2
fi

mod_name=$(sed -n 's/.*"name": "\([^"]*\)".*/\1/p' info.json)
if [[ -z "$mod_name" ]]; then
    echo "generate_release.sh: info.json has no mod name" >&2
    exit 2
fi
dir_name="${mod_name}_$1"
mkdir -p "$dir_name"
cp -r gui "$dir_name/gui"
cp -r locale "$dir_name/locale"
cp -r logic "$dir_name/logic"
cp changelog.txt "$dir_name/changelog.txt"
cp control.lua "$dir_name/control.lua"
cp data.lua "$dir_name/data.lua"
cp info.json "$dir_name/info.json"
cp LICENSE "$dir_name/LICENSE"
cp thumbnail.png "$dir_name/thumbnail.png"
cp settings.lua "$dir_name/settings.lua"
cp updates.lua "$dir_name/updates.lua"
sed -i -e "s/\"version\": \"[^\"]*\"/\"version\": \"$1\"/" \
    -e "s/\"factorio_version\": \"[^\"]*\"/\"factorio_version\": \"$2\"/" \
    "$dir_name/info.json"

# The packaged copy carries the commit it was built from, so an in-game observation can name the code that ran.
# The working tree never gets this file: a source checkout must report packaged = false (plan section 10).
# RRC_CANDIDATE_SHA is set by the builder, which archives a commit into a directory holding no .git.
candidate_sha=${RRC_CANDIDATE_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}
cat > "$dir_name/logic/build_id.lua" <<BUILD_ID
--Written by generate_release.sh into the packaged copy only; absent in a source checkout.
return {candidate_sha = "$candidate_sha", mod_version = "$1", factorio_branch = "$2", packaged = true}
BUILD_ID

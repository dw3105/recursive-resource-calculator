#!/bin/sh
# Download + unpack headless Factorio. usage: tools/fetch_factorio.sh (copied from sushi-packer-mod, same host binaries) <2.0|2.1>
set -eu
case "${1:?usage: tools/fetch_factorio.sh (copied from sushi-packer-mod, same host binaries) <2.0|2.1>}" in
  2.0) V=2.0.77; SIZE=57225308 ;;
  2.1) V=2.1.20; SIZE=60993508 ;;
  *) echo "FV must be 2.0 or 2.1" >&2; exit 2 ;;
esac
D=$HOME/factorio-$1
test -x "$D/factorio/bin/x64/factorio" && { "$D/factorio/bin/x64/factorio" --version | head -1; exit 0; }
mkdir -p "$D"
curl -sL -o "$D/factorio-headless_linux_$V.tar.xz" "https://www.factorio.com/get-download/$V/headless/linux64"
test "$(stat -c %s "$D/factorio-headless_linux_$V.tar.xz")" = "$SIZE" || { echo "size mismatch" >&2; exit 1; }
tar -xJf "$D/factorio-headless_linux_$V.tar.xz" -C "$D"
"$D/factorio/bin/x64/factorio" --version | head -1

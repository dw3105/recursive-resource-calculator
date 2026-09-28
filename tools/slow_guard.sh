#!/bin/sh
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 7
RRC_GUARD_TOOL=$1 RRC_GUARD_INPUT=${2:-} lua5.2 -e 'package.path="./?.lua;"..package.path; require("tools.lib.slow_guard").check(os.getenv("RRC_GUARD_TOOL"), os.getenv("RRC_GUARD_INPUT"))'

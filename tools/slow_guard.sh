#!/bin/sh
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 7
exec lua5.2 -e 'package.path="./?.lua;"..package.path; local tool,input=arg[0],arg[1]; require("tools.lib.slow_guard").check(tool,input)' "$1" "${2:-}"

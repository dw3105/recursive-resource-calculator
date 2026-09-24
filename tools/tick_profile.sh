#!/bin/sh
# Worst single tick per phase on one golden case (profile.lua copy in tools/). Usage: sh tools/tick_profile.sh <case>
lua5.2 tools/profile.lua "tests/golden/cases/${1:?case id}/prepared_input.json" 2>&1 | tail -9

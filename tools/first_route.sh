#!/bin/sh
# Fast check (round 41): the FIRST route verdict of one golden case. Usage: sh tools/first_route.sh <case>
# Prints FIRST-ROUTE ok=<bool> <codes> [flow= src= sink=]  or  FIRST-ROUTE none pack_fails=<n>
lua5.2 tools/first_stage.lua "${1:?case}" route "${2:-12}" 2>&1 >/dev/null | grep '^FIRST-ROUTE'

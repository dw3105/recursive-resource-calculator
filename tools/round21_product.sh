#!/bin/sh
# Round 21 product check: full generation on the player's sheet, encode, then judge the BYTES with
# tools/transport_shape_probe.py.  Prints `product-ok` only when generation returns ok=true with entities
# AND the bytes carry sideload=0 back_to_back=0 cycles=0.  Writes only under a mktemp directory.
# Usage: sh tools/round21_product.sh   (run from the repository root; about 200 s on legalcopilot-dev)
dir=$(mktemp -d)
lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s/prepared_input.json \
    --output "$dir/result.json" >"$dir/gen.out" 2>"$dir/gen.err"
python3 -c "import json,sys; r=json.load(open('$dir/result.json')); e=(r.get('result') or {}).get('entities') or []; print('ok=%s entities=%d' % (r.get('ok'), len(e))); sys.exit(0 if r.get('ok') is True and len(e) > 0 else 1)" \
    || { echo "product-fail: generation"; exit 1; }
python3 tools/blueprint_string.py "$dir/result.json" -o "$dir/bp.txt" >/dev/null 2>"$dir/enc.err" \
    || { echo "product-fail: encode $(head -1 "$dir/enc.err")"; exit 1; }
python3 tools/transport_shape_probe.py "$dir/bp.txt" -v || { echo "product-fail: shapes"; exit 1; }
python3 tools/blueprint_audit.py "$dir/bp.txt" | grep -E "^  (belts|undergrounds|splitters|entities|invalid_inserters|unused_belt_tiles) "
echo product-ok

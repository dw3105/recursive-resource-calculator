#!/bin/sh
# FactorioTest CLI 3.6.0 aborts when no test run starts within a hard-coded 10 s (FND-0005).
# A shared 4-vCPU host running 2-3 headless loads at once needs longer. Idempotent; run after `npm ci`.
set -eu
f=${FT_DIR:-$(dirname "$0")}/node_modules/factorio-test-cli/factorio-process.js
grep -q '}, 120_000);' "$f" && exit 0
sed -i 's/    }, 10_000);/    }, 120_000);/; s/no test run started within 10 seconds/no test run started within 120 seconds/' "$f"
grep -q '}, 120_000);' "$f" && echo "patched startup watchdog to 120 s"

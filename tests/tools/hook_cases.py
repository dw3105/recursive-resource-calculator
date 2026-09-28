#!/usr/bin/env python3
"""Cases for tools/claude_slow_hook.py (run: timeout 60 python3 tests/tools/hook_cases.py). Expected exit per case."""
import json, os, subprocess, sys, tempfile

HOOK = os.path.join(os.path.dirname(__file__), "..", "..", "tools", "claude_slow_hook.py")
CASES = [
    (0, "cd ~/wt-rrc-275 && git diff round-47-base HEAD -- tools/bytes_hash.sh tests/run.sh | head"),
    (0, "cd ~/wt-rrc-275 && cat tools/lib/slow_guard.lua tests/golden/generate.lua"),
    (2, "cd ~/wt-rrc-int && lua5.2 tests/test_seat.lua"),
    (0, "cd ~/wt-rrc-int && timeout 90 lua5.2 tests/test_seat.lua"),
    (2, "cd ~/wt-rrc-int && sh tools/bytes_hash.sh x"),
    (2, "cd ~/wt-rrc-int && timeout 90 lua5.2 tests/golden/generate.lua --input x"),
    (0, "cd ~/wt-rrc-int && (time timeout 99 lua5.2 tools/ckpt.lua resume a.gz) > x 2>&1"),
    (2, "cd ~/wt-rrc-int && timeout 600 lua5.2 tools/ckpt.lua resume a.gz"),
    (0, "cd ~/legalcopilot && lua5.2 foo.lua"),
    (2, "cd ~/wt-rrc-int && RRC_SLOW=profile:short lua5.2 tools/golden_profile.lua x y"),
]

def main():
    bad = 0
    with tempfile.TemporaryDirectory() as home:
        env = dict(os.environ, HOME=home)
        for want, cmd in CASES:
            p = subprocess.run([sys.executable, HOOK], input=json.dumps({"tool_input": {"command": cmd}, "cwd": "/x"}),
                               text=True, capture_output=True, env=env)
            ok = p.returncode == want
            bad += 0 if ok else 1
            print(("ok  " if ok else "BAD ") + "want=%d got=%d :: %s" % (want, p.returncode, cmd[:90]))
    print("hook cases: %d bad" % bad)
    sys.exit(1 if bad else 0)

if __name__ == "__main__":
    main()

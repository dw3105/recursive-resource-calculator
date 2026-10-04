#!/usr/bin/env python3
"""Claude Code PreToolUse(Bash) guard for RRC: fast checks by construction (player order 2026-09-28).

Rule 1: every RRC command that runs lua5.2 / tools/ / tests/ must start its heavy part with `timeout N`, N <= 120.
Rule 2: whole-sheet and gate tools (SLOW list) need `RRC_SLOW=<slot>:<reason>` (slot in budget, reason >= 20 chars);
        each allowed start is written to ~/.cache/rrc/slow_ledger.tsv and counted against tools/slow_budget per wave.
Exit 2 + stderr = deny (Claude sees the message). Anything not RRC passes untouched.
"""
import json, os, re, sys, time

FAST_HINT = ("fast rungs: static ckpt read (tools.lib.graph_dump.load), one-function stage replay on ckpt state, "
             "tools/route_replay_one.lua on one demand, validate-only `ckpt.lua resume <val ckpt>` under timeout 90, "
             "single `lua5.2 tests/<file>.lua`. See skill rrc-code RC-01.")
SLOW = [r"tests/golden/generate\.lua", r"tools/golden_profile\.lua", r"tools/ckpt\.lua\s+(save|list|uninterrupted)\b",
        r"tools/bytes_hash\.sh", r"bytes13\.sh", r"tools/gate_sheet\.sh", r"tools/measure_sheet\.sh",
        r"tools/speed_probe\.sh", r"tests/run\.sh", r"tools/game_test\.sh", r"gen_watch\.lua", r"tools/first_stage\.lua"]
BUDGET = {"profile": 1, "bytes": 1, "suite": 2, "headless": 1, "ckpt-save": 3, "release": 2}
MAX_TIMEOUT = 120
LEDGER = os.path.expanduser("~/.cache/rrc/slow_ledger.tsv")
WAVE_FILE = os.path.expanduser("~/.cache/rrc/wave")

def deny(msg):
    sys.stderr.write("RRC-SLOW-GUARD: " + msg + "\n" + FAST_HINT + "\n")
    sys.exit(2)

def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    cmd = (data.get("tool_input") or {}).get("command") or ""
    cwd = data.get("cwd") or ""
    rrc = re.search(r"wt-rrc|recursive-resource-calculator|rrc-round-\d+-probes|scratchpad/r4\d", cmd + " " + cwd)
    heavy = re.search(r"\blua5\.2\b|(^|[\s/])(tools|tests)/", cmd)
    if not rrc:
        return
    # Round 54: a per-row cap passed through the environment (TMO=300) and a decoy `timeout 110 true` both slipped
    # past rule 1 by wording. The cap is per check, however it is spelled.
    tmo = [int(n) for n in re.findall(r"\bTMO=[\"']?(\d+)", cmd)]
    if tmo and max(tmo) > MAX_TIMEOUT:
        deny("TMO=%d is a per-check timeout above %d s; rerun timed-out rows alone at low load" % (max(tmo), MAX_TIMEOUT))
    if re.search(r"\btimeout\s+(?:-\S+\s+)*\d+s?\s+(?:true|:)(?:\s|;|&|$)", cmd):
        deny("`timeout N true` caps nothing; put the timeout on the command that runs code")
    if not heavy:
        return
    # read-only inspection commands (cat/grep/sed/ls/diff/git) never run code: skip when no interpreter is invoked
    # An interpreter must START a command segment (after ; && || | ( and env/timeout prefixes). File names inside a
    # read-only command (`git diff a.sh tests/run.sh`) are not a run: the first hook blocked exactly that (2026-09-28).
    running = []
    # Shell keywords (if/while/do/!/{) also prefix a run: `if lua5.2 ...; then` slipped past (ticket 06, 2026-10-04).
    for seg in re.split(r"&&|\|\||[;|()\n]", cmd):
        words = seg.strip().split()
        while words and (re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]) or words[0] in ("timeout", "env", "time", "nice", "if", "then", "else", "elif", "while", "until", "do", "!", "{", "exec", "command", "builtin")
                         or re.match(r"^-|^\d+s?$", words[0])):
            words = words[1:]
        if words and (words[0] in ("lua5.2", "lua") or words[0].startswith("./tools/")
                      or (words[0] in ("sh", "bash", "python3") and len(words) > 1
                          and (re.match(r"^(\./)?(tools|tests)/", words[1])
                               or re.search(r"wt-rrc|recursive-resource-calculator|rrc-round-\d+-probes|scratchpad/r4\d", words[1])))):
            # orchestration tools outside the repo (lane.py under /var/lib/agent-skills) are not checks
            running.append(seg)
    if not running:
        return
    cmd_run = " ; ".join(running)
    slow_hit = [p for p in SLOW if re.search(p, cmd_run)]
    m = re.search(r"RRC_SLOW=[\"']([a-z-]+):([^\"']+)[\"']", cmd) or re.search(r"RRC_SLOW=([a-z-]+):(\S+)", cmd)
    if slow_hit:
        # goldens measured under 10 s CPU are fast checks (tools/slow_budget.json fast_cases); rule 1 still applies
        try:
            here = os.path.dirname(os.path.abspath(__file__))
            cands = [os.path.join(here, "slow_budget.json"), os.path.expanduser("~/wt-rrc-int/tools/slow_budget.json")]
            fast = next((json.load(open(c)).get("fast_cases", []) for c in cands if os.path.exists(c)), [])
        except Exception:
            fast = []
        named = re.findall(r"player-[a-z0-9-]+", cmd_run)
        if named and all(n in fast for n in named) and not m:
            slow_hit = []
    if slow_hit:
        if not m:
            deny("slow tool %s needs RRC_SLOW=<slot>:<reason>; slots %s. Ask: which fast rung cannot answer?"
                 % (re.sub(r"\\[sb]|\\|\+", " ", slow_hit[0]).strip(), ",".join(BUDGET)))
        slot, reason = m.group(1), m.group(2)
        if slot not in BUDGET:
            deny("unknown slot %r; slots %s" % (slot, ",".join(BUDGET)))
        if len(reason) < 20:
            deny("reason too short (%d chars); say why no fast rung answers" % len(reason))
        wave = open(WAVE_FILE).read().strip() if os.path.exists(WAVE_FILE) else "unset"
        # distinct runs, same rule as tools/lib/slow_guard.lua: one RRC_SLOW value = one run (children, loop steps)
        runs = set()
        if os.path.exists(LEDGER):
            for line in open(LEDGER):
                f = line.rstrip("\n").split("\t")
                if len(f) >= 5 and f[1] == wave and f[2] == slot:
                    runs.add(f[4])
        if reason in runs:
            return
        if len(runs) >= BUDGET[slot]:
            deny("slot %s budget %d used up in wave %s (ledger %s)" % (slot, BUDGET[slot], wave, LEDGER))
        os.makedirs(os.path.dirname(LEDGER), exist_ok=True)
        with open(LEDGER, "a") as fh:
            fh.write("\t".join([time.strftime("%Y-%m-%dT%H:%M:%S"), wave, slot, slow_hit[0].replace("\\", ""),
                                reason, cmd.replace("\n", " ")[:300]]) + "\n")
        return
    # Rule 1: fast by construction
    t = re.findall(r"\btimeout\s+(?:-\S+\s+)*(\d+)(s?)\b", cmd)
    if not t:
        deny("RRC command runs code without `timeout N` (N <= %d s). Fast checks only." % MAX_TIMEOUT)
    if max(int(n) for n, _ in t) > MAX_TIMEOUT:
        deny("timeout above %d s is not a fast check" % MAX_TIMEOUT)

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Write a round bytes baseline, requiring proof for every changed row."""
import re, sys

ROW = re.compile(r"^ROW case=(\S+) pack=(\S+) .*?sha=(\w+) .*?verdict=(\w+)$")
PROOF = re.compile(r"^PROOF case=(\S+) pack=(\S+) sha=(\w+) validate=ok lane_sim=0 lab=\S+/\S+ parity=(same|owed|drift)$")

def main(argv):
    if len(argv) != 4:
        raise SystemExit("usage: bytes_baseline.py <gate.log> <proof.log> <old baseline> <out>")
    gate, proof, old_path, out = argv
    old = {}
    for line in open(old_path, encoding="utf-8"):
        m=re.match(r"^BYTES (\S+) (\w+)$",line.strip())
        if m: old[m.group(1)]=m.group(2)
    proofs={}
    for line in open(proof,encoding="utf-8"):
        m=PROOF.match(line.strip())
        if m: proofs[(m.group(1),m.group(2))]=m.group(3)
    rows={}
    for line in open(gate,encoding="utf-8"):
        m=ROW.match(line.strip())
        if not m: continue
        case,pack,sha,verdict=m.groups()
        if verdict in ("SAME","DIFF"):
            if verdict=="DIFF" and proofs.get((case,pack))!=sha:
                raise SystemExit(f"DIFF row {case} lacks matching proof")
            rows[case]=sha if verdict=="DIFF" else next((v for c,v in old.items() if c==case and v.startswith(sha)),sha)
        elif verdict in ("SLOWER","FAIL"):
            if case in old: rows[case]=old[case]
    missing=[case for case in old if case not in rows]
    rows.update({case:old[case] for case in missing})
    with open(out,"w",encoding="utf-8") as f:
        for case in sorted(rows): f.write(f"BYTES {case} {rows[case]}\n")
    return 0

if __name__=="__main__":
    try: raise SystemExit(main(sys.argv[1:]))
    except OSError as e: raise SystemExit(str(e))

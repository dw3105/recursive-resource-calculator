#!/usr/bin/env python3
"""The player's exact mod set for headless sheet sims (round 48 I1, G5: exact captured versions, never latest).

  tools/fetch_player_mods.py lock [capture.json]   capture's environment.active_mods -> tests/player_mods.lock.json
  tools/fetch_player_mods.py fetch                 download locked zips into ~/share/RRC/player-mods/2.0, sha1 checked
  tools/fetch_player_mods.py list                  locked mod names, one per line

Capture default: docs/incidents/2026-09-20-search-budget/payload.json (only capture carrying the player's 54 mods,
RRC 1.1.51, base 2.0.77). RRC-Fork is never fetched: the sim stages this tree. Download needs ~/.factorio-portal
(username=..., token=...), chmod 600, never in repo. Ported from ~/sushi-packer-mod/tools/fetch_mods.py.
"""
import hashlib, json, os, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCK = os.path.join(ROOT, "tests", "player_mods.lock.json")
CAPTURE = os.path.join(ROOT, "docs", "incidents", "2026-09-20-search-budget", "payload.json")
CACHE = os.path.expanduser(os.environ.get("RRC_PLAYER_MODS", "~/share/RRC/player-mods/2.0"))
BUILTIN = {"base", "space-age", "quality", "elevated-rails", "recycler", "core"}
OURS = {"RRC-Fork"}
API = "https://mods.factorio.com/api/mods/%s/full"


def api(name):
    req = urllib.request.Request(API % name, headers={"User-Agent": "rrc-fetch/1"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def active_mods(path):
    def find(o):
        if isinstance(o, dict):
            if isinstance(o.get("active_mods"), dict):
                return o["active_mods"]
            for v in o.values():
                r = find(v)
                if r:
                    return r
        if isinstance(o, list):
            for v in o:
                r = find(v)
                if r:
                    return r
        return None
    mods = find(json.load(open(path)))
    if not mods:
        raise SystemExit(f"fetch_player_mods: no environment.active_mods in {path}")
    return mods


def dep_name(dep):
    dep = dep.strip()
    if dep[:1] in "?!" or dep.startswith("(?)"):
        return None
    return dep.lstrip("~+ ").strip().split()[0]


def cmd_lock(capture):
    mods = active_mods(capture)
    lock, missing_deps = {"_capture": os.path.relpath(capture, ROOT), "_base": mods.get("base"), "mods": {}}, []
    for name in sorted(mods):
        if name in BUILTIN or name in OURS:
            continue
        want = mods[name]
        rel = [r for r in api(name)["releases"] if r["version"] == want]
        if not rel:
            raise SystemExit(f"fetch_player_mods: {name} {want} not on the portal")
        r = rel[0]
        lock["mods"][name] = {"version": want, "file": r["file_name"], "sha1": r["sha1"], "url": r["download_url"]}
        for d in (dep_name(x) for x in r["info_json"].get("dependencies", [])):
            if d and d not in mods and d not in BUILTIN:
                missing_deps.append(f"{name} needs {d}")
    lock["_missing_required_deps"] = sorted(set(missing_deps))
    json.dump(lock, open(LOCK, "w"), indent=2, sort_keys=True)
    open(LOCK, "a").write("\n")
    print(len(lock["mods"]), "mods locked;", len(lock["_missing_required_deps"]), "missing required deps")
    for line in lock["_missing_required_deps"]:
        print("  missing:", line)


def creds():
    p = os.path.expanduser("~/.factorio-portal")
    kv = dict(l.strip().split("=", 1) for l in open(p) if "=" in l)
    return kv["username"], kv["token"]


def sha1(p):
    h = hashlib.sha1()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def cmd_fetch():
    lock = json.load(open(LOCK))["mods"]
    os.makedirs(CACHE, exist_ok=True)
    user = token = None
    for name in sorted(lock):
        e = lock[name]
        p = os.path.join(CACHE, e["file"])
        if os.path.exists(p) and sha1(p) == e["sha1"]:
            continue
        if user is None:
            user, token = creds()
        url = "https://mods.factorio.com%s?username=%s&token=%s" % (e["url"], user, token)
        tmp = p + ".part"
        req = urllib.request.Request(url, headers={"User-Agent": "rrc-fetch/1"})  # default urllib UA gets 403
        with urllib.request.urlopen(req, timeout=600) as r, open(tmp, "wb") as f:
            while True:
                b = r.read(1 << 20)
                if not b:
                    break
                f.write(b)
        got = sha1(tmp)
        if got != e["sha1"]:
            os.remove(tmp)
            raise SystemExit(f"fetch_player_mods: sha1 mismatch {e['file']}: {got} != {e['sha1']}")
        os.replace(tmp, p)
        print("fetched", e["file"], os.path.getsize(p), flush=True)
    print("fetch-player-mods-ok", len(lock))


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["lock"] and len(a) <= 2:
        cmd_lock(a[1] if len(a) == 2 else CAPTURE)
    elif a == ["fetch"]:
        cmd_fetch()
    elif a == ["list"]:
        print("\n".join(sorted(json.load(open(LOCK))["mods"])))
    else:
        raise SystemExit(__doc__)

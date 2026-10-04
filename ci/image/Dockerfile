# syntax=docker/dockerfile:1.7
FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive
ARG FACTORIO_20=2.0.77
ARG FACTORIO_21=2.1.20

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl xz-utils lua5.2 python3 python3-pip python3-venv nodejs npm git \
    libasound2 libx11-6 libxext6 libxrender1 libxrandr2 libxi6 \
    build-essential libstdc++6 && \
    rm -rf /var/lib/apt/lists/*

ENV RRC_FACTORIO_20="${FACTORIO_20}" \
    RRC_FACTORIO_21="${FACTORIO_21}" \
    RRC_PLAYER_MODS=/opt/rrc/player-mods/2.0 \
    RRC_FT_DIR=/opt/rrc/factorio-test \
    FT_ZIP_DIR=/opt/rrc/factorio-test-mods \
    PATH=/workspace:$PATH

RUN mkdir -p /opt/factorio/2.0.77 /opt/factorio/2.1.20 /root/factorio-2.0 /root/factorio-2.1 && \
    curl -fsSL "https://factorio.com/get-download/${FACTORIO_20}/headless/linux64" -o /tmp/factorio-20.tar.xz && \
    tar -xJf /tmp/factorio-20.tar.xz -C /opt/factorio/2.0.77 --strip-components=1 && \
    curl -fsSL "https://factorio.com/get-download/${FACTORIO_21}/headless/linux64" -o /tmp/factorio-21.tar.xz && \
    tar -xJf /tmp/factorio-21.tar.xz -C /opt/factorio/2.1.20 --strip-components=1 && \
    ln -s /opt/factorio/2.0.77 /root/factorio-2.0/factorio && \
    ln -s /opt/factorio/2.1.20 /root/factorio-2.1/factorio && \
    rm /tmp/factorio-20.tar.xz /tmp/factorio-21.tar.xz

WORKDIR /workspace
COPY . /workspace
COPY tests/player_mods.lock.json /opt/rrc/player_mods.lock.json

# The mod portal credentials are supplied by the image builder as a BuildKit secret; never baked into a layer.
RUN --mount=type=secret,id=factorio_portal,target=/root/.factorio-portal \
    RRC_PLAYER_MODS=/opt/rrc/player-mods/2.0 python3 tools/fetch_player_mods.py fetch

# FactorioTest's game-side runner is separate from its Node CLI. Pin both game-compatible mod archives by version.
RUN --mount=type=secret,id=factorio_portal,target=/root/.factorio-portal \
    python3 - <<'PY'
import hashlib, json, os, urllib.parse, urllib.request

credentials = dict(line.strip().split("=", 1) for line in open("/root/.factorio-portal") if "=" in line)
os.makedirs("/opt/rrc/factorio-test-mods", exist_ok=True)
releases = json.load(urllib.request.urlopen(
    "https://mods.factorio.com/api/mods/factorio-test/full", timeout=60))["releases"]
for version in ("3.0.1", "3.1.0"):
    release = next(item for item in releases if item["version"] == version)
    query = urllib.parse.urlencode({"username": credentials["username"], "token": credentials["token"]})
    url = "https://mods.factorio.com" + release["download_url"] + "?" + query
    request = urllib.request.Request(url, headers={"User-Agent": "rrc-image/1"})
    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            data = response.read()
    except Exception as error:
        raise SystemExit(f"FactorioTest {version} download failed ({type(error).__name__})") from None
    actual = hashlib.sha1(data).hexdigest()
    if actual != release["sha1"]:
        raise SystemExit(f"FactorioTest {version} SHA1 mismatch: {actual}")
    path = f"/opt/rrc/factorio-test-mods/factorio-test_{version}.zip"
    with open(path, "wb") as output:
        output.write(data)
PY

RUN mkdir -p /opt/rrc/factorio-test && \
    cp tools/ft/package.json tools/ft/package-lock.json tools/ft/patch-cli.sh /opt/rrc/factorio-test/ && \
    cd /opt/rrc/factorio-test && npm ci && FT_DIR=/opt/rrc/factorio-test sh patch-cli.sh

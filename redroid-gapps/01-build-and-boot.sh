#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Redroid 11 + real Google Play Services, built on your VPS.
# Produces a single image tag: redroid/redroid:11.0.0-gapps
# Play Services lives INSIDE the image, so it is present on every container
# boot with no post-start scripting.
#
# Run on the VPS as root:  bash 01-build-and-boot.sh
# ---------------------------------------------------------------------------
set -euo pipefail

WORKDIR="$HOME/redroid-gapps"
IMAGE="redroid/redroid:11.0.0-gapps"
CONTAINER="redroid_google_instance"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[fatal]\033[0m %s\n' "$*" >&2; exit 1; }

# --- 0. sanity -------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "must run as root"
command -v docker >/dev/null || die "docker not found"

say "Environment"
docker --version
df -h / | tail -n 1
free -m | sed -n '1,2p'
need_gb=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
if [ "${need_gb:-0}" -lt 6 ]; then
  warn "Less than 6 GB free on /. The GApps image needs ~1 GB plus extraction headroom."
  a=""
  read -rp "Continue anyway? [y/N] " a || true
  [ "${a:-}" = y ] || die "aborted"
fi

# --- 1. remove the broken INPUT rule that shadows Docker's DNAT -----------
# Earlier debugging inserted "iptables -I INPUT ... --dport 5555 -j ACCEPT".
# Because INPUT is traversed before DOCKER's chain, that rule bypasses
# NAT and silently kills the published port. Remove it properly.
say "Repairing iptables (removing stray port-5555 INPUT rules)"
if command -v iptables >/dev/null; then
  n=0; guard=0
  while [ "$guard" -lt 20 ]; do
    line=$(iptables -S INPUT 2>/dev/null | grep -n -- '--dport 5555' | cut -d: -f1 | head -1 || true)
    [ -n "$line" ] || break
    if iptables -D INPUT "$line" 2>/dev/null; then
      n=$((n+1))
    else
      break
    fi
    guard=$((guard+1))
  done
  echo "removed $n stray rule(s)"
  # Do NOT run `iptables -F` or `iptables -t nat -F` here. That wipes
  # Docker's NAT table and breaks every published port on the host.
else
  warn "iptables not found, skipping"
fi

# --- 2. stop everything from previous attempts -----------------------------
say "Stopping previous containers"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker rm -f redroid_google_instance >/dev/null 2>&1 || true

say "Restarting docker so it re-reads iptables"
systemctl restart docker
sleep 5

# --- 3. dependencies -------------------------------------------------------
say "Installing build dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq lzip git curl >/dev/null
echo "lzip: $(command -v lzip)"

# --- 4. build the GApps image ---------------------------------------------
# ayasa520/redroid-script injects OpenGApps into the system partition and
# commits a new image. It does not recompile Android from source.
say "Fetching redroid-script"
mkdir -p "$WORKDIR"
cd "$WORKDIR"
[ -d redroid-script ] && rm -rf redroid-script
git clone --depth 1 https://github.com/ayasa520/redroid-script
cd redroid-script

say "Building GApps image (this takes 5-15 min on 3 cores)"
python3 redroid.py -a 11.0.0 -g

docker image inspect "$IMAGE" >/dev/null 2>&1 \
  || die "build finished but $IMAGE is missing - scroll up for the script's error"

say "Image built"
docker images "$IMAGE"

# --- 5. clean data volume --------------------------------------------------
# The old instance was killed mid-boot repeatedly. A half-initialised
# /data can boot-loop and close adbd, which is what made 5555 look dead.
say "Resetting data partition"
cd "$WORKDIR"
docker run --rm -v "$WORKDIR/data":/data alpine:3 sh -c 'rm -rf /data/* /data/.[!.]* 2>/dev/null || true'
mkdir -p "$WORKDIR/data"

# --- 6. boot ---------------------------------------------------------------
say "Starting container"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d \
  --name "$CONTAINER" \
  --privileged \
  --restart always \
  -v "$WORKDIR/data":/data \
  -p 5555:5555 \
  "$IMAGE" \
  androidboot.redroid_gpu_mode=guest \
  androidboot.redroid_fps=30 \
  androidboot.redroid_width=720 \
  androidboot.redroid_height=1280 \
  ro.product.cpu.abilist=x86_64,x86,armeabi-v7a,armeabi \
  ro.product.cpu.abilist64=x86_64 \
  ro.product.cpu.abilist32=x86,armeabi-v7a,armeabi

say "Waiting for Android framework to come up (60s)"
sleep 60

# --- 7. verify -------------------------------------------------------------
say "Verification"
docker ps --filter "name=$CONTAINER" --format 'status: {{.Status}}'

if docker exec "$CONTAINER" pm path com.google.android.gms >/dev/null 2>&1; then
  echo "Play Services: INSTALLED"
  docker exec "$CONTAINER" dumpsys package com.google.android.gms \
    | grep -m1 versionName | sed 's/^ */Play Services version: /'
else
  die "com.google.android.gms not present - the GApps injection did not land"
fi

echo
echo "Settings > Accounts > Add account should now list Google."

# Play Protect certification. An uncertified device blocks some Play features
# but NOT the Add Account screen, so this is optional and manual.
cat <<'NOTE'

NEXT (optional, manual): Play Protect certification
  On the VPS:
    adb connect 127.0.0.1:5555
    adb root
    adb shell 'sqlite3 /data/data/com.google.android.gsf/databases/gservices.db \
      "select * from main where name = \"android_id\";"'
  Take the printed android_id to https://www.google.com/android/uncertified
  and register it. Wait ~15 min, then clear Play Store / Play Services data.

NEXT: from your Windows machine
  powershell -File connect.ps1

NEXT (only if you want traffic to exit via your proxy)
  bash 02-proxy.sh
NOTE

say "Done"

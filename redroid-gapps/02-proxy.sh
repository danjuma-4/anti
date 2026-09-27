#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# OPTIONAL. Apply your proxy to the Android container from the inside.
#
# Why not a sibling proxy container: putting Android behind another
# container's network namespace (gluetun / redsocks / tun2socks) is what
# made port 5555 intermittently refuse connections. Setting the proxy on
# the device itself leaves adb's port forward untouched.
#
# Why not the compose `environment:` block: Android does not read
# http_proxy from the container environment. Only the Settings database
# is honoured.
#
# Usage:  bash 02-proxy.sh set gate.nodemaven.com 1132
#         bash 02-proxy.sh off
# ---------------------------------------------------------------------------
set -euo pipefail

CONTAINER="redroid_google_instance"
cmd="${1:-}"

adb_() { docker exec "$CONTAINER" "$@"; }

alive() {
  docker exec "$CONTAINER" settings get global http_proxy >/dev/null 2>&1
}

case "$cmd" in
  set)
    host="${2:?usage: 02-proxy.sh set <host> <port>}"
    port="${3:?usage: 02-proxy.sh set <host> <port>}"
    alive || { echo "container not responding - is it up? (docker ps)"; exit 1; }

    echo "applying $host:$port"
    adb_ settings put global http_proxy "$host:$port"
    adb_ settings put global global_http_proxy_host "$host"
    adb_ settings put global global_http_proxy_port "$port"

    # Keep loopback, the local adb bridge, and the host gateway direct.
    # Without this, Android routes its own internal traffic through the
    # proxy and the adb daemon loses its socket - that is what produced
    # "device offline" and white screens in earlier attempts.
    adb_ settings put global global_http_proxy_exclude_list \
      "localhost,127.0.0.1,10.0.2.2,172.17.0.1,192.168.0.0/16"

    # Nudge already-running apps and browsers to reload the setting.
    adb_ am broadcast -a android.intent.action.PROXY_CHANGE >/dev/null 2>&1 || true

    echo
    echo "verify from the device, in the browser:"
    echo "  https://ipinfo.io"
    echo "  https://whoer.net"
    echo
    echo "This persists in ./data and survives container restarts."
    echo "Undo with:  bash 02-proxy.sh off"
    ;;

  off)
    alive || { echo "container not responding"; exit 1; }
    echo "clearing proxy"
    adb_ settings put global http_proxy :0
    adb_ settings delete global http_proxy  >/dev/null 2>&1 || true
    adb_ settings delete global global_http_proxy_host >/dev/null 2>&1 || true
    adb_ settings delete global global_http_proxy_port >/dev/null 2>&1 || true
    adb_ settings delete global global_http_proxy_exclude_list >/dev/null 2>&1 || true
    adb_ am broadcast -a android.intent.action.PROXY_CHANGE >/dev/null 2>&1 || true
    echo "cleared"
    ;;

  show)
    alive || { echo "container not responding"; exit 1; }
    echo "http_proxy: $(adb_ settings get global http_proxy)"
    echo "exclude:    $(adb_ settings get global global_http_proxy_exclude_list)"
    ;;

  *)
    echo "usage:"
    echo "  bash 02-proxy.sh set <host> <port>"
    echo "  bash 02-proxy.sh off"
    echo "  bash 02-proxy.sh show"
    exit 1
    ;;
esac

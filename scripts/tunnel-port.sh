#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# tunnel-port.sh — Expose a local port publicly via ngrok or Cloudflare.
#
# Usage:
#   tunnel-port <port>                      ngrok (default)
#   tunnel-port --ngrok <port>              ngrok (explicit)
#   tunnel-port --cf <subdomain> <port>     <subdomain>.$TUNNEL_CF_DOMAIN via Cloudflare
#   tunnel-port --cf -v <subdomain> <port>  same, with per-request debug logging
#
# Config (injected by modules/home/shell.nix from private.nix):
#   TUNNEL_CF_DOMAIN     apex domain managed in Cloudflare DNS
#   TUNNEL_CF_NAME       name of the locally-managed cloudflared tunnel
#   TUNNEL_NGROK_DOMAIN  reserved ngrok domain ("" = random per run)
# ─────────────────────────────────────────────────────────────

backend=ngrok
case "${1:-}" in
  --ngrok) backend=ngrok; shift ;;
  --cf)    backend=cf;    shift ;;
esac

if [ "$backend" = cf ]; then
  : "${TUNNEL_CF_DOMAIN:?TUNNEL_CF_DOMAIN not set}"
  : "${TUNNEL_CF_NAME:?TUNNEL_CF_NAME not set}"

  loglevel=info
  if [ "${1:-}" = "-v" ] || [ "${1:-}" = "--verbose" ]; then
    loglevel=debug
    shift
  fi

  sub="${1:-}"
  port="${2:-}"
  if [ -z "$sub" ] || [ -z "$port" ]; then
    echo "usage: tunnel-port --cf [-v] <subdomain> <port>" >&2
    exit 1
  fi

  host="${sub}.${TUNNEL_CF_DOMAIN}"
  echo "→ ${host}  →  http://localhost:${port}   (tunnel: ${TUNNEL_CF_NAME}, loglevel: ${loglevel})"

  # Route the subdomain to this tunnel (idempotent — ignore 'record already exists').
  # The DNS route is what maps $host → the tunnel; --url sets the (catch-all)
  # service the tunnel proxies to. --hostname is ignored for named tunnels.
  cloudflared tunnel route dns "$TUNNEL_CF_NAME" "$host" 2>/dev/null || true
  # --metrics pinned to loopback so the only listening socket is never exposed
  # to the LAN (default is 127.0.0.1 on bare metal but 0.0.0.0 in containers).
  # --url is a connect target (loopback), not a listener.
  exec cloudflared tunnel --loglevel "$loglevel" \
    --metrics 127.0.0.1:0 \
    --url "http://localhost:${port}" run "$TUNNEL_CF_NAME"
else
  port="${1:-}"
  if [ -z "$port" ]; then
    echo "usage: tunnel-port [--ngrok] <port>" >&2
    exit 1
  fi

  if [ -z "${TUNNEL_NGROK_DOMAIN:-}" ]; then
    exec ngrok http "$port"
  else
    exec ngrok http --domain="$TUNNEL_NGROK_DOMAIN" "$port"
  fi
fi

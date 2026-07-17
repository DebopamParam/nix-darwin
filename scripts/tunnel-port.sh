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
# Cloudflare mode uses ONE TUNNEL PER SUBDOMAIN (named
# $TUNNEL_CF_NAME-<subdomain>), created on first use, each with its own
# credentials JSON and its own config file under ~/.cloudflared/tunnel-port/.
# Rerunning a subdomain TAKES OVER: any previous cloudflared for that
# tunnel is killed first, so the latest run always wins.
#
# Why per-subdomain: a single shared tunnel with a merged ingress config
# breaks because locally-managed cloudflared reads ingress only at startup
# and Cloudflare load-balances across all connectors of a tunnel — two
# overlapping runs at different config states served divergent ingress,
# causing intermittent 404s. Per-subdomain tunnels have no shared mutable
# state: replicas of one tunnel are identical by construction.
#
# Config (injected by modules/home/shell.nix from private.nix):
#   TUNNEL_CF_DOMAIN     apex domain managed in Cloudflare DNS
#   TUNNEL_CF_NAME       prefix for per-subdomain tunnel names (distinct per machine!)
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
  name="${TUNNEL_CF_NAME}-${sub}"
  config_dir="$HOME/.cloudflared/tunnel-port"
  config="${config_dir}/${sub}.yml"

  lookup_tunnel_id() {
    # `tunnel list --name` returns literal `null` (not []) on no match,
    # hence the `(. // [])` guard before iterating.
    cloudflared tunnel list --name "$name" --output json 2>/dev/null \
      | jq -r --arg n "$name" '[(. // [])[] | select(.name == $n)][0].id // empty'
  }

  tunnel_id="$(lookup_tunnel_id)"
  if [ -z "$tunnel_id" ]; then
    cloudflared tunnel create "$name" >/dev/null
    tunnel_id="$(lookup_tunnel_id)"
  fi
  if [ -z "$tunnel_id" ]; then
    echo "failed to create or find tunnel '$name'" >&2
    exit 1
  fi

  credentials_file="$HOME/.cloudflared/${tunnel_id}.json"
  if [ ! -f "$credentials_file" ]; then
    echo "credentials file $credentials_file missing — tunnel '$name' exists but was created elsewhere." >&2
    echo "run: cloudflared tunnel delete $name   and retry" >&2
    exit 1
  fi

  # Repoint DNS at this tunnel; --overwrite-dns handles records left over
  # from a previous tunnel. Errors are intentionally NOT swallowed.
  cloudflared tunnel route dns --overwrite-dns "$name" "$host"

  mkdir -p "$config_dir"
  cat >"$config" <<EOF
tunnel: ${tunnel_id}
credentials-file: ${credentials_file}

ingress:
  - hostname: ${host}
    service: http://localhost:${port}
  - service: http_status:404
EOF

  # Takeover: latest run wins for this subdomain.
  pids="$(pgrep -f "cloudflared .* run ${name}\$" || true)"
  if [ -n "$pids" ]; then
    echo "replacing existing tunnel-port for ${sub} (pid ${pids})" >&2
    kill $pids || true
    for _ in $(seq 1 25); do
      pgrep -f "cloudflared .* run ${name}\$" >/dev/null || break
      sleep 0.2
    done
  fi

  echo "→ ${host}  →  http://localhost:${port}   (tunnel: ${name}, loglevel: ${loglevel})"
  echo "config: ${config}"

  # --metrics pinned to loopback so the only listening socket is never exposed
  # to the LAN (default is 127.0.0.1 on bare metal but 0.0.0.0 in containers).
  exec cloudflared tunnel --loglevel "$loglevel" \
    --metrics 127.0.0.1:0 \
    --config "$config" run "$name"
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

#!/usr/bin/env bash
# Requires ccstatusline installed once: `npm i -g ccstatusline`
# (Avoid `npx -y ccstatusline@latest` here — it hits the registry on every render.)
if command -v ccstatusline >/dev/null 2>&1; then
  cc_output=$(ccstatusline 2>/dev/null)
else
  cc_output="ccstatusline not installed (npm i -g ccstatusline)"
fi
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
email=$(jq -r '.oauthAccount.emailAddress // empty' "$config_dir/.claude.json" 2>/dev/null)
[[ -n "$email" ]] && echo "$cc_output | $email" || echo "$cc_output"

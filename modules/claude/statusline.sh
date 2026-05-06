#!/usr/bin/env bash
cc_output=$(node "$(npm root -g)/ccstatusline/dist/ccstatusline.js" 2>/dev/null)
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
email=$(jq -r '.oauthAccount.emailAddress // empty' "$config_dir/.claude.json" 2>/dev/null)
[[ -n "$email" ]] && echo "$cc_output | $email" || echo "$cc_output"

#!/usr/bin/env bash
# Render a Mermaid diagram (.mmd) to a high-DPI (3x) PNG using ephemeral
# `nix shell nixpkgs#mermaid-cli`, with sandbox-safe Chromium flags and optional
# theme config JSON (`"theme": "base"` + `themeVariables`).
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <input.mmd> <output.png> [mermaid-config.json] [scale]" >&2
  exit 1
fi

INPUT="$1"
OUTPUT="$2"
CONFIG_FILE="${3:-}"
SCALE="${4:-3}"

if [ ! -w "${XDG_CACHE_HOME:-$HOME/.cache}" ] 2>/dev/null; then
  export XDG_CACHE_HOME="$(mktemp -d /tmp/nix-cache.XXXXXX)"
fi

PUPPETEER_CFG="$(mktemp /tmp/mmdc-puppeteer.XXXXXX.json)"
trap 'rm -f "$PUPPETEER_CFG"' EXIT

cat >"$PUPPETEER_CFG" <<'EOF'
{
  "args": [
    "--no-sandbox",
    "--disable-setuid-sandbox",
    "--disable-dev-shm-usage",
    "--disable-gpu"
  ]
}
EOF

EXTRA_ARGS=()
if [ -n "$CONFIG_FILE" ]; then
  EXTRA_ARGS+=("-c" "$CONFIG_FILE")
fi

mkdir -p "$(dirname "$OUTPUT")"

nix shell nixpkgs#mermaid-cli -c mmdc \
  -i "$INPUT" \
  -o "$OUTPUT" \
  -s "$SCALE" \
  -b transparent \
  -p "$PUPPETEER_CFG" \
  "${EXTRA_ARGS[@]}"

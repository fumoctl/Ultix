#!/usr/bin/env bash
# Execute a Node.js script with `docx` and `image-size` available in an
# ephemeral /tmp workspace via `nix shell nixpkgs#nodejs` (zero global packages,
# zero node_modules clutter in the user's project directory).
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <script.cjs> [args...]" >&2
  exit 1
fi

if [ ! -w "${XDG_CACHE_HOME:-$HOME/.cache}" ] 2>/dev/null; then
  export XDG_CACHE_HOME="$(mktemp -d /tmp/nix-cache.XXXXXX)"
fi

ENV_DIR="/tmp/docx-skill-node-env"
mkdir -p "$ENV_DIR"

nix shell nixpkgs#nodejs -c bash -c '
  set -euo pipefail
  ENV_DIR="$1"
  shift
  if [ ! -d "$ENV_DIR/node_modules/docx" ] || [ ! -d "$ENV_DIR/node_modules/image-size" ]; then
    (
      cd "$ENV_DIR"
      if [ ! -f package.json ]; then
        printf "{\"name\":\"docx-skill-env\",\"private\":true}\n" > package.json
      fi
      npm install --no-audit --no-fund --loglevel=error "docx@^9.5.0" "image-size@^1.2.1" >/dev/null
    )
  fi
  export NODE_PATH="$ENV_DIR/node_modules${NODE_PATH:+:$NODE_PATH}"
  exec node "$@"
' _ "$ENV_DIR" "$@"

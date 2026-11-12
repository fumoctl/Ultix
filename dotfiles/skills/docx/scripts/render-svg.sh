#!/usr/bin/env bash
# Rasterize a custom SVG figure, diagram, or cover graphic to a crisp high-DPI
# PNG using ephemeral `nix shell nixpkgs#resvg` and system fontconfig.
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <input.svg> <output.png> [zoom]" >&2
  exit 1
fi

INPUT="$1"
OUTPUT="$2"
ZOOM="${3:-3}"

if [ ! -w "${XDG_CACHE_HOME:-$HOME/.cache}" ] 2>/dev/null; then
  export XDG_CACHE_HOME="$(mktemp -d /tmp/nix-cache.XXXXXX)"
fi

mkdir -p "$(dirname "$OUTPUT")"

nix shell nixpkgs#resvg -c resvg -z "$ZOOM" "$INPUT" "$OUTPUT"

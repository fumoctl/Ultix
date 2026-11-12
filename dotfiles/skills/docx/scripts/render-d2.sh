#!/usr/bin/env bash
# Render a D2 architecture/schema diagram (.d2) to a crisp 3x PNG via SVG +
# resvg using ephemeral `nix shell nixpkgs#d2 nixpkgs#resvg` (fast, browserless).
# Rewrites D2's embedded WOFF2 @font-face aliases (which are already quoted in
# D2's CSS) to single installed system font family names so resvg renders text
# cleanly without browser overhead.
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <input.d2> <output.png> [extra d2 flags...]" >&2
  exit 1
fi

INPUT="$1"
OUTPUT="$2"
shift 2

if [ ! -w "${XDG_CACHE_HOME:-$HOME/.cache}" ] 2>/dev/null; then
  export XDG_CACHE_HOME="$(mktemp -d /tmp/nix-cache.XXXXXX)"
fi

TMP_SVG="$(mktemp /tmp/d2-diagram.XXXXXX.svg)"
trap 'rm -f "$TMP_SVG"' EXIT

mkdir -p "$(dirname "$OUTPUT")"

nix shell nixpkgs#d2 nixpkgs#resvg -c bash -c '
  set -euo pipefail
  INPUT="$1"
  TMP_SVG="$2"
  OUTPUT="$3"
  shift 3
  d2 --pad 24 "$@" "$INPUT" "$TMP_SVG" >/dev/null
  sed -E -i \
    -e "s/d2-[0-9]+-font-mono/JetBrainsMono Nerd Font/g" \
    -e "s/d2-[0-9]+-font-[a-zA-Z]+/Noto Sans/g" \
    "$TMP_SVG"
  resvg -z 3 "$TMP_SVG" "$OUTPUT"
' _ "$INPUT" "$TMP_SVG" "$OUTPUT" "$@"

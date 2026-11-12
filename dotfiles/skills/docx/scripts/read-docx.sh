#!/usr/bin/env bash
# Extract structured Markdown content from an existing .docx file using
# ephemeral `nix shell nixpkgs#pandoc`.
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <input.docx> [extra pandoc args...]" >&2
  exit 1
fi

if [ ! -w "${XDG_CACHE_HOME:-$HOME/.cache}" ] 2>/dev/null; then
  export XDG_CACHE_HOME="$(mktemp -d /tmp/nix-cache.XXXXXX)"
fi

nix shell nixpkgs#pandoc -c pandoc "$1" -t markdown --wrap=none "${@:2}"

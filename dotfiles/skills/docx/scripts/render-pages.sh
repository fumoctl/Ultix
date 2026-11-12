#!/usr/bin/env bash
# Convert a .docx file to PDF and per-page PNG images for visual QA using
# ephemeral `nix shell nixpkgs#libreoffice-still nixpkgs#poppler-utils`.
# Uses a disposable LibreOffice profile in /tmp so ~/.config/libreoffice is
# never created in $HOME.
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <input.docx> <output-dir> [dpi]" >&2
  exit 1
fi

INPUT="$(realpath "$1")"
OUT_DIR="$2"
DPI="${3:-150}"

if [ ! -w "${XDG_CACHE_HOME:-$HOME/.cache}" ] 2>/dev/null; then
  export XDG_CACHE_HOME="$(mktemp -d /tmp/nix-cache.XXXXXX)"
fi

LO_PROF="$(mktemp -d /tmp/lo-docx-profile.XXXXXX)"
trap 'rm -rf "$LO_PROF"' EXIT

mkdir -p "$OUT_DIR"
OUT_DIR_ABS="$(realpath "$OUT_DIR")"
STEM="$(basename "${INPUT%.*}")"
PDF_PATH="$OUT_DIR_ABS/$STEM.pdf"

rm -f "$OUT_DIR_ABS"/page-*.png "$PDF_PATH"

nix shell nixpkgs#libreoffice-still nixpkgs#poppler-utils -c bash -c '
  set -euo pipefail
  soffice "-env:UserInstallation=file://$1" --headless --convert-to pdf --outdir "$2" "$3" >/dev/null
  pdftoppm -png -r "$4" "$5" "$2/page"
' _ "$LO_PROF" "$OUT_DIR_ABS" "$INPUT" "$DPI" "$PDF_PATH"

ls -1 "$OUT_DIR_ABS"/page-*.png

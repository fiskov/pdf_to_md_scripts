#!/usr/bin/env bash
# convert_docling.sh — batch convert all PDFs from input/ to output/ as
# LLM-friendly Markdown using docling.
#
# Usage:
#   ./convert_docling.sh                                            # input/ -> output/, placeholders
#   ./convert_docling.sh --images referenced                        # images as PNG files
#   ./convert_docling.sh --images embedded SRC_DIR DST_DIR          # images inline (base64)
#
# Image modes (--image-export-mode of docling):
#   placeholder  (default) <!-- image --> markers; smallest output, best for LLM context
#   referenced   PNG files saved to <name>_artifacts/ next to the md; links are
#                rewritten to ./-relative so they survive moving the folder;
#                visible in VSCode/Typora/Obsidian and other markdown viewers
#   embedded     images inlined as base64; single portable file, much larger
#
# Locates docling in .venv-docling (created by install_docling.sh), then .venv,
# then anywhere on PATH.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\033[1;32m[convert]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: ./convert_docling.sh [--images placeholder|embedded|referenced] [SRC_DIR DST_DIR]
  SRC_DIR   defaults to ./input  (next to this script)
  DST_DIR   defaults to ./output
  --images  placeholder (default, best for LLM) | referenced (PNG files next to
            the md, viewable in editors) | embedded (inline base64, large file)
EOF
}

IMAGES_MODE="placeholder"
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --images)   IMAGES_MODE="${2:-}"; shift 2 ;;
        --images=*) IMAGES_MODE="${1#*=}"; shift ;;
        -h|--help)  usage; exit 0 ;;
        -*)         usage >&2; fail "unknown option: $1" ;;
        *)          ARGS+=("$1"); shift ;;
    esac
done
case "$IMAGES_MODE" in
    placeholder|embedded|referenced) ;;
    *) usage >&2; fail "--images must be placeholder, embedded or referenced (got: '$IMAGES_MODE')" ;;
esac
[ "${#ARGS[@]}" -le 2 ] || { usage >&2; fail "too many arguments (max SRC_DIR DST_DIR)"; }

INPUT_DIR="${ARGS[0]:-$SCRIPT_DIR/input}"
OUTPUT_DIR="${ARGS[1]:-$SCRIPT_DIR/output}"

[ -d "$INPUT_DIR" ] || fail "input folder not found: $INPUT_DIR"

# --- locate docling -----------------------------------------------------------
if [ -x "$SCRIPT_DIR/.venv-docling/bin/docling" ]; then
    DOCLING="$SCRIPT_DIR/.venv-docling/bin/docling"
elif [ -x "$SCRIPT_DIR/.venv/bin/docling" ]; then
    DOCLING="$SCRIPT_DIR/.venv/bin/docling"
elif command -v docling >/dev/null 2>&1; then
    DOCLING="$(command -v docling)"
else
    fail "docling not found — run ./install_docling.sh first (or activate a venv that has docling)"
fi

# absolutize: docling writes absolute image links in referenced mode, so the
# output path must be stable regardless of where the script is invoked from
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

# --- collect PDFs (case-insensitive: .pdf / .PDF) ------------------------------
shopt -s nullglob nocaseglob
files=( "$INPUT_DIR"/*.pdf )
shopt -u nullglob nocaseglob

[ "${#files[@]}" -gt 0 ] || fail "no PDFs found in $INPUT_DIR"

log "docling: $DOCLING"
log "${#files[@]} file(s): $INPUT_DIR -> $OUTPUT_DIR (images: $IMAGES_MODE)"

# --- convert ---------------------------------------------------------------------
failures=0
for f in "${files[@]}"; do
    name="$(basename "$f")"
    echo
    log "--- $name"
    start=$SECONDS
    if "$DOCLING" convert "$f" --to md --image-export-mode "$IMAGES_MODE" --output "$OUTPUT_DIR"; then
        if [ "$IMAGES_MODE" = "referenced" ] && [ -f "$OUTPUT_DIR/${name%.*}.md" ]; then
            # docling writes absolute image paths; rewrite to ./-relative so the
            # markdown stays valid if the folder is moved or cloned from git
            sed -i "s|$OUTPUT_DIR/|./|g" "$OUTPUT_DIR/${name%.*}.md"
        fi
        log "OK  $name ($((SECONDS - start))s)"
    else
        printf '\033[1;31m[convert]\033[0m FAIL %s (%ss)\n' "$name" "$((SECONDS - start))" >&2
        failures=$((failures + 1))
    fi
done

echo
log "done: $(( ${#files[@]} - failures )) ok, $failures failed"
[ "$failures" -eq 0 ]

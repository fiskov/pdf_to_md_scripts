#!/usr/bin/env bash
# install_docling.sh — standalone installer for docling (PDF -> Markdown)
#
# Usage:
#   ./install_docling.sh                   # CPU build + download AI models
#   ./install_docling.sh file.pdf          # ... + smoke-test conversion
#   ./install_docling.sh --gpu [file.pdf]  # CUDA-enabled torch build (see below)
#
# --gpu installs the default PyPI torch, which bundles the CUDA runtime
# (~2.5 GB download, ~6 GB venv; needs a recent NVIDIA driver). docling picks
# the GPU up automatically — the verify step reports if CUDA is unavailable.
# Default (no flag) is the CPU-only build: ~10x smaller, runs anywhere.
#
# Environment overrides:
#   VENV_DIR=.venv-docling  target venv directory (default: .venv-docling)
#   PYTHON_BIN=python3     python interpreter to use (default: python3)
#   DOCLING_GPU=1          same as --gpu
#
# After install, convert PDFs either with the CLI:
#   .venv-docling/bin/docling convert FILE.pdf --to md --image-export-mode placeholder --output output_dir
# or from Python:
#   from docling.document_converter import DocumentConverter
#   md = DocumentConverter().convert("FILE.pdf").document.export_to_markdown()

set -euo pipefail

VENV_DIR="${VENV_DIR:-.venv-docling}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

usage() {
    cat <<'EOF'
Usage: ./install_docling.sh [--gpu] [SMOKE_TEST.pdf]
  --gpu          install CUDA-enabled PyTorch (default PyPI build) instead of
                 the CPU-only build; docling then uses the GPU automatically.
  SMOKE_TEST.pdf optional PDF converted at the end as a smoke test.
Env overrides: VENV_DIR (default .venv-docling), PYTHON_BIN (default python3),
DOCLING_GPU=1 (same as --gpu).
EOF
}

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# --- arguments -----------------------------------------------------------------
GPU="${DOCLING_GPU:-0}"
SMOKE_PDF=""
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --gpu)     GPU=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*)        usage >&2; fail "unknown option: $1" ;;
        *)         ARGS+=("$1"); shift ;;
    esac
done
[ "${#ARGS[@]}" -le 1 ] || { usage >&2; fail "too many arguments (at most one smoke-test PDF)"; }
SMOKE_PDF="${ARGS[0]:-}"

# --- preconditions -----------------------------------------------------------
command -v "$PYTHON_BIN" >/dev/null 2>&1 \
    || fail "'$PYTHON_BIN' not found. Install Python 3.10+ and/or set PYTHON_BIN."
"$PYTHON_BIN" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' \
    || fail "Python 3.10+ required (found $("$PYTHON_BIN" --version))."

if [ -e "$VENV_DIR" ]; then
    fail "'$VENV_DIR' already exists — remove it or set VENV_DIR to a new path."
fi

# --- 1. venv + pip -----------------------------------------------------------
log "Creating venv in $VENV_DIR"
"$PYTHON_BIN" -m venv "$VENV_DIR"
PIP="$VENV_DIR/bin/pip"
"$PIP" install --quiet --upgrade pip

# --- 2. PyTorch (CPU or GPU) ----------------------------------------------------
# torch AND torchvision must come from the same index/build: mixing a +cpu torch
# with a PyPI (CUDA-built) torchvision breaks compiled ops
# ("operator torchvision::nms does not exist").
# CPU (default): small wheels from the PyTorch CPU index (~200 MB, venv ~1.8 GB).
# GPU (--gpu): default PyPI wheels bundle the CUDA runtime (~2.5 GB download,
# venv ~6 GB); docling uses CUDA automatically when available.
if [ "$GPU" -eq 1 ]; then
    log "Installing GPU (CUDA) PyTorch + matching torchvision (default PyPI build)"
    command -v nvidia-smi >/dev/null 2>&1 \
        || log "WARNING: nvidia-smi not found — no NVIDIA driver detected, CUDA will not work here"
    "$PIP" install --quiet torch torchvision
else
    log "Installing CPU-only PyTorch + matching torchvision"
    "$PIP" install --quiet torch torchvision --index-url https://download.pytorch.org/whl/cpu
fi

# --- 3. docling ---------------------------------------------------------------
# Pin the installed builds via constraints so pip cannot swap torch/torchvision
# for a different variant from PyPI while resolving docling's dependencies.
CONSTRAINTS="$VENV_DIR/.torch-constraints"
"$PIP" freeze | grep -E '^(torch|torchvision)==' > "$CONSTRAINTS"
log "Installing docling (torch pinned to: $(paste -sd', ' "$CONSTRAINTS" | sed 's/==/ /g'))"
"$PIP" install --quiet docling -c "$CONSTRAINTS"

# --- 4. pre-download AI models -------------------------------------------------
# Layout/TableFormer/OCR models come from Hugging Face on first conversion.
# Downloading them here makes the first real conversion fast and lets you
# verify network access to HF before pointing it at your documents.
log "Downloading docling AI models (~1 GB, cached in ~/.cache/huggingface)"
"$VENV_DIR/bin/docling-tools" models download

# --- 5. verify -----------------------------------------------------------------
log "Verifying imports"
"$VENV_DIR/bin/python" - <<'EOF'
import torch, torchvision, docling
# run a real compiled op; raises on torch/torchvision build mismatch
torchvision.ops.nms(torch.tensor([[0., 0., 1., 1.]]), torch.tensor([0.9]), 0.5)
from docling.document_converter import DocumentConverter
print(f"  torch {torch.__version__} (cuda available: {torch.cuda.is_available()})")
print(f"  torchvision {torchvision.__version__}")
print(f"  docling {docling.__version__}")
EOF

if [ "$GPU" -eq 1 ]; then
    if "$VENV_DIR/bin/python" -c "import torch; raise SystemExit(0 if torch.cuda.is_available() else 1)"; then
        log "CUDA is available — docling will use the GPU"
    else
        log "WARNING: --gpu was requested but CUDA is not available."
        log "         The install still works (runs on CPU). Check the NVIDIA driver."
    fi
fi

# --- 6. optional smoke test ------------------------------------------------------
if [ -n "$SMOKE_PDF" ]; then
    [ -f "$SMOKE_PDF" ] || fail "Smoke-test file '$SMOKE_PDF' not found."
    log "Smoke test: converting $SMOKE_PDF (expect a few seconds per page on CPU)"
    # placeholder keeps <!-- image --> markers instead of multi-MB base64 blobs
    "$VENV_DIR/bin/docling" convert "$SMOKE_PDF" --to md --image-export-mode placeholder --output smoke_out
    log "Smoke test output written to $(pwd)/smoke_out/"
fi

log "Done. Convert PDFs with:"
log "  $VENV_DIR/bin/docling convert FILE.pdf --to md --image-export-mode placeholder --output OUTPUT_DIR"

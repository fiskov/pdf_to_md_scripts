# PDF → Markdown (for LLM)

## Folders

| Folder | Contents |
|---|---|
| `input/` | source PDFs |
| `markdown/` | output of **pymupdf4llm** (the fast option, ~25× faster than docling) |
| `output/` | output of **docling** (best table and structure quality) |

## Scripts

| File | Purpose |
|---|---|
| `convert_to_md.py` | pymupdf4llm: all PDFs from `input/` → `markdown/` |
| `install_docling.sh` / `install_docling.ps1` | install docling (CPU or GPU torch build) + download models |
| `convert_docling.sh` / `convert_docling.ps1` | docling: all PDFs from `input/` → `output/` |

## Linux

Install docling (creates the `.venv-docling` venv, downloads ~1 GB of models):

```bash
./install_docling.sh                    # CPU build (default, venv ~1.8 GB)
./install_docling.sh --gpu              # NVIDIA GPU: CUDA-enabled torch (venv ~6 GB)
# optional smoke test: append a PDF path, e.g. ./install_docling.sh --gpu test.pdf
```

Convert the whole folder:

```bash
./convert_docling.sh                                    # input/ → output/, <!-- image --> placeholders (best for LLM)
./convert_docling.sh --images referenced                # images as PNG files next to the md (viewable in editors)
./convert_docling.sh --images embedded SRC_DIR DST_DIR  # images inline base64 (single file, much larger)
```

Single direct command (swap `placeholder` for `referenced` or `embedded` if needed):

```bash
.venv-docling/bin/docling convert "input/FILE.pdf" --to md --image-export-mode placeholder --output output
```

## Windows (PowerShell)

Install (installs Python 3.12 via winget if missing):

```powershell
powershell -ExecutionPolicy Bypass -File .\install_docling.ps1            # CPU build
powershell -ExecutionPolicy Bypass -File .\install_docling.ps1 -UseGpu    # NVIDIA GPU
# with smoke test: ... -SmokePdf C:\path\to\file.pdf
```

Convert the whole folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\convert_docling.ps1                        # placeholders (LLM)
powershell -ExecutionPolicy Bypass -File .\convert_docling.ps1 -Images referenced     # PNG files (viewable)
powershell -ExecutionPolicy Bypass -File .\convert_docling.ps1 -Images embedded       # inline base64
# custom folders: add -InputDir C:\in -OutputDir C:\out
```

Single direct command:

```powershell
.venv-docling\Scripts\docling.exe convert FILE.pdf --to md --image-export-mode placeholder --output output
```

## Fast option: pymupdf4llm

```bash
python3 -m venv .venv
.venv/bin/pip install pymupdf4llm
.venv/bin/python convert_to_md.py       # input/ → markdown/
```

(On Windows: `python -m venv .venv` → `.venv\Scripts\python convert_to_md.py`)

## Notes

- **Image modes** (`--images` / `-Images`):
  - `placeholder` (default) — `<!-- image -->` markers; smallest output, best for LLM context;
  - `referenced` — PNGs in `<name>_artifacts/` next to the md; the convert scripts rewrite links to `./`-relative so they keep working after the folder is moved or cloned; visible in VSCode/Typora/Obsidian;
  - `embedded` — images inlined as base64 (a 141 KB markdown balloons to 2.8 MB); single portable file.
- **GPU (`--gpu` / `-UseGpu`)**: installs the default PyPI torch, which bundles the CUDA runtime (~2.5 GB download, venv ~6 GB); requires a recent NVIDIA driver. docling uses CUDA automatically — the installer warns if `torch.cuda.is_available()` is False. Roughly 5–10× faster conversion than CPU.
- docling on CPU: roughly 3–6 s/page. The first conversion may download models from Hugging Face.
- No need to install torch separately — the installers pull `torch`+`torchvision` as a matched pair (CPU index or PyPI) and pin them via constraints (mixing a CPU torch with a CUDA-built torchvision from PyPI breaks).
- **markitdown** is not suitable for these datasheets: it doesn't understand two-column layouts and generates garbage tables (verified on CH32V208DS0).
- Quality comparison on CH32V208DS0: pymupdf4llm — good tables, `#` headings, 14 s; docling — best tables (pin mapping aligned by column), 82 headings, ~5 min.

# install_docling.ps1 - standalone installer for docling (PDF -> Markdown), Windows
#
# Run from PowerShell (accept the one-time execution-policy bypass):
#   powershell -ExecutionPolicy Bypass -File .\install_docling.ps1
#   powershell -ExecutionPolicy Bypass -File .\install_docling.ps1 -SmokePdf C:\path\to\file.pdf
#   powershell -ExecutionPolicy Bypass -File .\install_docling.ps1 -UseGpu
#
# What it does:
#   1. Finds Python 3.10+ (py launcher / PATH / standard install dirs);
#      if missing, installs Python 3.12 via winget.
#   2. Creates a venv ".venv-docling" and upgrades pip.
#   3. Installs torch + torchvision (matched pair): CPU build by default, or the
#      CUDA-bundled PyPI build with -UseGpu (~2.5 GB download, venv ~6 GB,
#      needs a recent NVIDIA driver; docling then uses the GPU automatically).
#   4. Installs docling with those torch builds pinned (prevents variant swap-in).
#   5. Pre-downloads the docling AI models (~1 GB).
#   6. Verifies imports and runs a real torchvision compiled op.
#   7. Optionally smoke-tests a conversion with -SmokePdf.
#
# Optional env overrides:  $env:VENV_DIR = "my-venv"  before running.

param(
    [string]$SmokePdf = "",
    [switch]$UseGpu
)

$ErrorActionPreference = "Stop"
$VenvDir = if ($env:VENV_DIR) { $env:VENV_DIR } else { ".venv-docling" }

function Log($msg)  { Write-Host "[install] $msg" -ForegroundColor Green }
function Fail($msg) { Write-Host "[error] $msg" -ForegroundColor Red; exit 1 }

# --- 1. locate (or install) Python 3.10+ ---------------------------------------
function Test-Python($exe) {
    & $exe -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)"
    return ($LASTEXITCODE -eq 0)
}

function Find-PythonExe {
    # py launcher first (standard with python.org / winget installs)
    if (Get-Command py -ErrorAction SilentlyContinue) {
        $exe = & py -3 -c "import sys; print(sys.executable)"
        if ($LASTEXITCODE -eq 0 -and $exe -and (Test-Python $exe)) { return $exe }
    }
    # plain python on PATH (skip the Windows Store alias stub in WindowsApps)
    $plain = Get-Command python -ErrorAction SilentlyContinue
    if ($plain -and $plain.Source -notlike "*\WindowsApps\*") {
        if (Test-Python $plain.Source) { return $plain.Source }
    }
    # standard install locations, newest first
    $patterns = @(
        "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe",
        "$env:ProgramFiles\Python3*\python.exe",
        "${env:ProgramFiles(x86)}\Python3*\python.exe"
    )
    foreach ($pattern in $patterns) {
        $found = @(Get-Item $pattern -ErrorAction SilentlyContinue)
        foreach ($exe in ($found | Sort-Object -Property FullName -Descending)) {
            if (Test-Python $exe.FullName) { return $exe.FullName }
        }
    }
    return $null
}

$pythonExe = Find-PythonExe
if (-not $pythonExe) {
    Log "Python 3.10+ not found - installing Python 3.12 via winget"
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Fail "winget not available. Install Python 3.10+ manually from https://www.python.org/downloads/ (tick 'Add python.exe to PATH') and re-run this script."
    }
    & winget install -e --id Python.Python.3.12 --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) {
        Fail "winget Python install failed. Install manually from https://www.python.org/downloads/ and re-run."
    }
    # winget updates PATH in the registry, not in this process - reload it
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")
    $pythonExe = Find-PythonExe
    if (-not $pythonExe) { Fail "Python was installed but not detected. Open a NEW terminal and re-run this script." }
}
Log "Using Python: $pythonExe"

# --- 2. venv + pip ---------------------------------------------------------------
if (Test-Path $VenvDir) {
    Fail "'$VenvDir' already exists - remove it or set `$env:VENV_DIR to a new path."
}
Log "Creating venv in $VenvDir"
& $pythonExe -m venv $VenvDir
$PyVenv = Join-Path $VenvDir "Scripts\python.exe"

& $PyVenv -m pip install --quiet --upgrade pip
if ($LASTEXITCODE -ne 0) { Fail "pip upgrade failed." }

# --- 3. PyTorch (CPU or GPU) ------------------------------------------------------
# torch AND torchvision must come from the same index/build: mixing a +cpu torch
# with a PyPI (CUDA-built) torchvision breaks compiled ops
# ("operator torchvision::nms does not exist").
if ($UseGpu) {
    Log "Installing GPU (CUDA) PyTorch + matching torchvision (default PyPI build)"
    if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
        Write-Host "[install] WARNING: nvidia-smi not found - no NVIDIA driver detected, CUDA will not work here" -ForegroundColor Yellow
    }
    & $PyVenv -m pip install --quiet torch torchvision
    if ($LASTEXITCODE -ne 0) { Fail "PyTorch GPU install failed." }
} else {
    Log "Installing CPU-only PyTorch + matching torchvision"
    & $PyVenv -m pip install --quiet torch torchvision --index-url https://download.pytorch.org/whl/cpu
    if ($LASTEXITCODE -ne 0) { Fail "PyTorch CPU install failed." }
}

# --- 4. docling -------------------------------------------------------------------
# Pin the installed builds via constraints so pip cannot swap torch/torchvision
# for a different variant from PyPI while resolving docling's dependencies.
$constraintsPath = Join-Path $VenvDir "torch-constraints.txt"
$pins = (& $PyVenv -m pip freeze) | Where-Object { $_ -match "^(torch|torchvision)==" }
$pins | Set-Content -Path $constraintsPath -Encoding ascii
Log ("Installing docling (pinned: " + ($pins -join ", ") + ")")
& $PyVenv -m pip install --quiet docling -c $constraintsPath
if ($LASTEXITCODE -ne 0) { Fail "docling install failed." }

# --- 5. pre-download AI models ------------------------------------------------------
Log "Downloading docling AI models (~1 GB, cached under ~\.cache\huggingface)"
& (Join-Path $VenvDir "Scripts\docling-tools.exe") models download
if ($LASTEXITCODE -ne 0) { Fail "model download failed (check network access to huggingface.co)." }

# --- 6. verify ------------------------------------------------------------------------
Log "Verifying imports"
$check = @'
import torch, torchvision, docling
torchvision.ops.nms(torch.tensor([[0., 0., 1., 1.]]), torch.tensor([0.9]), 0.5)
from docling.document_converter import DocumentConverter
print(f"  torch {torch.__version__} (cuda available: {torch.cuda.is_available()})")
print(f"  torchvision {torchvision.__version__}")
print(f"  docling {docling.__version__}")
'@
& $PyVenv -c $check
if ($LASTEXITCODE -ne 0) { Fail "verification failed - see output above." }

if ($UseGpu) {
    & $PyVenv -c "import torch; raise SystemExit(0 if torch.cuda.is_available() else 1)"
    if ($LASTEXITCODE -eq 0) {
        Log "CUDA is available - docling will use the GPU"
    } else {
        Write-Host "[install] WARNING: -UseGpu was requested but CUDA is not available." -ForegroundColor Yellow
        Write-Host "[install]         The install still works (runs on CPU). Check the NVIDIA driver." -ForegroundColor Yellow
    }
}

# --- 7. optional smoke test --------------------------------------------------------------
if ($SmokePdf -ne "") {
    if (-not (Test-Path $SmokePdf)) { Fail "Smoke-test file '$SmokePdf' not found." }
    $SmokePdfAbs = (Resolve-Path $SmokePdf).Path
    Log "Smoke test: converting $SmokePdfAbs (CPU: expect a few seconds per page)"
    # placeholder keeps <!-- image --> markers instead of multi-MB base64 blobs
    & (Join-Path $VenvDir "Scripts\docling.exe") convert $SmokePdfAbs --to md --image-export-mode placeholder --output smoke_out
    if ($LASTEXITCODE -ne 0) { Fail "smoke-test conversion failed." }
    Log ("Smoke test output written to " + (Join-Path (Get-Location).Path "smoke_out"))
}

Log "Done. Convert PDFs with:"
Log ("  " + (Join-Path $VenvDir "Scripts\docling.exe") + " convert FILE.pdf --to md --image-export-mode placeholder --output OUTPUT_DIR")

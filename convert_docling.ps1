# convert_docling.ps1 - batch convert all PDFs from input\ to output\ as
# LLM-friendly Markdown using docling, Windows.
#
# Run:
#   powershell -ExecutionPolicy Bypass -File .\convert_docling.ps1
#   powershell -ExecutionPolicy Bypass -File .\convert_docling.ps1 -Images referenced
#   powershell -ExecutionPolicy Bypass -File .\convert_docling.ps1 -InputDir C:\in -OutputDir C:\out
#
# Image modes (-Images): placeholder (default, best for LLM) | referenced (PNG
# files in <name>_artifacts\ next to the md, viewable in editors) | embedded
# (inline base64, large file).
#
# Locates docling in .venv-docling (created by install_docling.ps1), then .venv,
# then anywhere on PATH.

param(
    [string]$InputDir = "",
    [string]$OutputDir = "",
    [ValidateSet("placeholder", "embedded", "referenced")]
    [string]$Images = "placeholder"
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
if (-not $InputDir)  { $InputDir  = Join-Path $ScriptDir "input" }
if (-not $OutputDir) { $OutputDir = Join-Path $ScriptDir "output" }
# absolutize: docling writes absolute image links in referenced mode, so the
# output path must be stable regardless of where the script is invoked from
if (-not [System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir = Join-Path (Get-Location).Path $OutputDir }

function Log($msg)  { Write-Host "[convert] $msg" -ForegroundColor Green }
function Fail($msg) { Write-Host "[error] $msg" -ForegroundColor Red; exit 1 }

if (-not (Test-Path $InputDir)) { Fail "input folder not found: $InputDir" }

# --- locate docling -------------------------------------------------------------
$docling = $null
foreach ($v in @(".venv-docling", ".venv")) {
    $cand = Join-Path $ScriptDir (Join-Path $v "Scripts\docling.exe")
    if (Test-Path $cand) { $docling = $cand; break }
}
if (-not $docling) {
    $cmd = Get-Command docling -ErrorAction SilentlyContinue
    if ($cmd) { $docling = $cmd.Source }
    else { Fail "docling not found - run .\install_docling.ps1 first (or activate a venv that has docling)" }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# --- collect PDFs (-Filter is case-insensitive on Windows: .pdf / .PDF) -----------
$files = @(Get-ChildItem -Path $InputDir -Filter *.pdf | Sort-Object Name)
if ($files.Count -eq 0) { Fail "no PDFs found in $InputDir" }

Log ("docling: " + $docling)
Log ($files.Count.ToString() + " file(s): " + $InputDir + " -> " + $OutputDir + " (images: " + $Images + ")")

# --- convert ------------------------------------------------------------------------
$failures = 0
foreach ($f in $files) {
    Write-Host ""
    Log ("--- " + $f.Name)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $docling convert $f.FullName --to md --image-export-mode $Images --output $OutputDir
    if ($LASTEXITCODE -eq 0) {
        if ($Images -eq "referenced") {
            $mdOut = Join-Path $OutputDir ([System.IO.Path]::GetFileNameWithoutExtension($f.Name) + ".md")
            if (Test-Path $mdOut) {
                # docling writes absolute image paths; rewrite to .\-relative so
                # the markdown stays valid if the folder is moved or cloned
                $content = Get-Content -Raw -Path $mdOut
                $content = $content.Replace($OutputDir + '\', '.\').Replace($OutputDir + '/', './')
                Set-Content -NoNewline -Path $mdOut -Value $content
            }
        }
        Log ("OK  " + $f.Name + " (" + [int]$sw.Elapsed.TotalSeconds + "s)")
    } else {
        Write-Host ("[convert] FAIL " + $f.Name) -ForegroundColor Red
        $failures++
    }
}

Write-Host ""
Log ("done: " + ($files.Count - $failures) + " ok, " + $failures + " failed")
if ($failures -ne 0) { exit 1 }

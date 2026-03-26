# build-standalone.ps1 — Build a self-contained NeuroMorphicToolkit installer for Windows.
#
# This script:
#   1. Downloads a standalone Python interpreter (python-build-standalone)
#   2. Builds the Flutter desktop app for Windows
#   3. Bundles Python + all module source code into the release directory
#   4. (Optional) Compiles the Inno Setup installer
#
# Usage: .\build-standalone.ps1 [-SkipFlutter] [-NoInstaller]
#
# Prerequisites: Flutter SDK, Git, Inno Setup (ISCC.exe in PATH)

param(
    [switch]$SkipFlutter,
    [switch]$NoInstaller
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..\..\..")
$ToolkitDir = Join-Path $RepoRoot "nmtk\neuro_toolkit"
$ReleaseDir = Join-Path $ToolkitDir "build\windows\x64\runner\Release"

# Python version to bundle
$PythonVersion = "3.12.7"
$PythonRelease = "20241016"
$PythonArch = "x86_64" # We only support x64 for now
$PythonTarball = "cpython-$PythonVersion+$PythonRelease-$PythonArch-pc-windows-msvc-shared-install_only.tar.gz"
$PythonUrl = "https://github.com/indygreg/python-build-standalone/releases/download/$PythonRelease/$PythonTarball"

$CacheDir = Join-Path $RepoRoot ".cache\python-standalone"
$PythonCache = Join-Path $CacheDir $PythonTarball
$PythonExtractDir = Join-Path $CacheDir "python-$PythonArch"

Write-Host "==> Starting Windows Standalone Build" -ForegroundColor Cyan

# --- Download standalone Python ---
if (-not (Test-Path $PythonExtractDir)) {
    Write-Host "==> Downloading standalone Python $PythonVersion..." -ForegroundColor Yellow
    if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Path $CacheDir | Out-Null }
    if (-not (Test-Path $PythonCache)) {
        Invoke-WebRequest -Uri $PythonUrl -OutFile $PythonCache
    }
    Write-Host "==> Extracting Python..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $PythonExtractDir | Out-Null
    # Note: Windows 'tar' (bsdtar) supports .tar.gz
    tar -xzf $PythonCache -C $PythonExtractDir
} else {
    Write-Host "==> Using cached Python at $PythonExtractDir" -ForegroundColor Green
}

$PythonRoot = Join-Path $PythonExtractDir "python"

# --- Build Flutter app ---
if (-not $SkipFlutter) {
    Write-Host "==> Building Flutter Windows app..." -ForegroundColor Yellow
    Push-Location $ToolkitDir
    flutter pub get
    flutter build windows --release
    Pop-Location
} else {
    Write-Host "==> Skipping Flutter build (-SkipFlutter)" -ForegroundColor Gray
}

if (-not (Test-Path $ReleaseDir)) {
    Write-Error "Release directory not found at $ReleaseDir"
    exit 1
}

# --- Bundle Python into Release dir ---
Write-Host "==> Bundling Python into release directory..." -ForegroundColor Yellow
$DestPythonDir = Join-Path $ReleaseDir "python"
if (Test-Path $DestPythonDir) { Remove-Item -Recurse -Force $DestPythonDir }
Copy-Item -Recurse -Path $PythonRoot -Destination $DestPythonDir

# Slim down Python to save space
Write-Host "==> Trimming Python bundle..." -ForegroundColor Gray
$TrimPaths = @(
    "Lib\test",
    "Lib\idlelib",
    "Lib\turtledemo",
    "Lib\site-packages\tkinter",
    "tcl"
)
foreach ($path in $TrimPaths) {
    $fullPath = Join-Path $DestPythonDir $path
    if (Test-Path $fullPath) { Remove-Item -Recurse -Force $fullPath }
}

# --- Bundle module source code ---
Write-Host "==> Bundling module source code..." -ForegroundColor Yellow
$DestModulesDir = Join-Path $ReleaseDir "modules"
if (Test-Path $DestModulesDir) { Remove-Item -Recurse -Force $DestModulesDir }
New-Item -ItemType Directory -Path $DestModulesDir | Out-Null

$Modules = @("neurocnl", "Neurosim", "Neurochip", "Neurobench", "Neurosense", "Neurohub", "Neuro-Dream-Hand")

foreach ($mod in $Modules) {
    $Src = Join-Path $RepoRoot $mod
    $Dest = Join-Path $DestModulesDir $mod

    if (-not (Test-Path $Src)) {
        Write-Warning "  Warning: $Src not found, skipping"
        continue
    }

    Write-Host "  Copying $mod..." -ForegroundColor Gray

    # Use robocopy for efficient copying with excludes
    # /E = recursive, /PURGE = delete dest files not in source, /NJH /NJS = quiet, /XD = exclude dirs
    $ExcludeDirs = @(".git", "venv", "build", "__pycache__", "node_modules", ".dart_tool", "frontend\build", "frontend\.dart_tool", ".mypy_cache", ".ruff_cache", ".pytest_cache")
    robocopy $Src $Dest /E /XD $ExcludeDirs /XF "*.pyc" "*.egg-info" /R:2 /W:5 /NFL /NDL /NJH /NJS | Out-Null
}

# --- Create Installer ---
if (-not $NoInstaller) {
    Write-Host "==> Creating Installer with Inno Setup..." -ForegroundColor Yellow
    $ISCC = "ISCC.exe"
    # Check if ISCC is in path, otherwise look in common install locations
    if (-not (Get-Command $ISCC -ErrorAction SilentlyContinue)) {
        $PossiblePaths = @(
            "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
            "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
        )
        foreach ($p in $PossiblePaths) {
            if (Test-Path $p) {
                $ISCC = $p
                break
            }
        }
    }

    if (Get-Command $ISCC -ErrorAction SilentlyContinue) {
        $IssPath = Join-Path $ScriptDir "setup.iss"
        & $ISCC $IssPath
        Write-Host "==> Installer created successfully!" -ForegroundColor Green
    } else {
        Write-Warning "ISCC.exe not found. Skipping installer creation. Please install Inno Setup 6."
    }
}

Write-Host "`n==> Build process complete!" -ForegroundColor Green
Write-Host "    Release artifacts are in: $ReleaseDir"

# setup.ps1 — One-command NeuroCNL setup for Windows
# Usage: iwr https://raw.githubusercontent.com/yoshimartodihardjo/Neuro-space/main/scripts/setup.ps1 | iex
#    or: .\setup.ps1 [-Version "v0.3.0"]

param(
    [string]$Version = "latest"
)

$ErrorActionPreference = "Stop"

$Arch = if ([Environment]::Is64BitOperatingSystem) { "x86_64" } else {
    Write-Error "32-bit Windows is not supported"
    exit 1
}

$BaseUrl = "https://github.com/yoshimartodihardjo/Neuro-space/releases"
if ($Version -eq "latest") {
    $BaseUrl = "$BaseUrl/latest/download"
} else {
    $BaseUrl = "$BaseUrl/download/$Version"
}

$InstallDir = Join-Path $env:LOCALAPPDATA "NeuroCNL"
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

Write-Host "`n🧠 NeuroCNL Setup" -ForegroundColor Cyan
Write-Host "   Version: $Version"
Write-Host "   Platform: windows-$Arch"
Write-Host "   Install dir: $InstallDir`n"

# Download backend
$BackendFile = "neurocnl-server-windows-$Arch.tar.gz"
Write-Host "⬇️  Downloading NeuroCNL Server..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -Uri "$BaseUrl/$BackendFile" -OutFile (Join-Path $InstallDir $BackendFile)
} catch {
    Write-Warning "Backend download failed. Try: pip install neurocnl[server]"
}

# Download frontend
$FrontendFile = "neurocnl-studio-windows.tar.gz"
Write-Host "⬇️  Downloading NeuroCNL Studio..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -Uri "$BaseUrl/$FrontendFile" -OutFile (Join-Path $InstallDir $FrontendFile)
} catch {
    Write-Warning "Frontend download failed."
}

# Extract
Write-Host "📦 Extracting..." -ForegroundColor Yellow
Push-Location $InstallDir
if (Test-Path $BackendFile) {
    tar xzf $BackendFile
    Remove-Item $BackendFile
}
if (Test-Path $FrontendFile) {
    tar xzf $FrontendFile
    Remove-Item $FrontendFile
}
Pop-Location

# Add to PATH suggestion
$PathEntry = $InstallDir
$CurrentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($CurrentPath -notlike "*$PathEntry*") {
    Write-Host "`n💡 Add to PATH (optional):" -ForegroundColor Cyan
    Write-Host "   [Environment]::SetEnvironmentVariable('PATH', `"$PathEntry;`$env:PATH`", 'User')"
}

Write-Host "`n✅ Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "  To start the backend server:"
Write-Host "    $InstallDir\neurocnl-server.exe --port 8000"
Write-Host ""
Write-Host "  To launch the studio:"
Write-Host "    $InstallDir\neurocnl-studio.exe"
Write-Host ""
Write-Host "  Or use Docker:"
Write-Host "    docker run -p 8000:8000 ghcr.io/yoshimartodihardjo/neurocnl-server:latest"
Write-Host ""
Write-Host "  Or install via pip:"
Write-Host "    pip install neurocnl[server]"
Write-Host "    neurocnl-server --port 8000"
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

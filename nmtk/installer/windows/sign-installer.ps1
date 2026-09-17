<#
.SYNOPSIS
    Sign the NeuroMorphicToolKit Windows installer using signtool.exe.

.DESCRIPTION
    Wraps signtool.exe for Authenticode signing of the NMTK .exe installer.
    Mirrors the structure of scripts/sign-and-notarize.sh (macOS).

.PARAMETER InstallerPath
    Path to the .exe installer to sign.

.PARAMETER Thumbprint
    SHA-1 thumbprint of the code-signing certificate in the Windows cert store.

.PARAMETER TimestampUrl
    RFC 3161 timestamp server URL (default: http://timestamp.digicert.com).

.PARAMETER DryRun
    Print the signtool command without executing it.

.PARAMETER Check
    Verify prerequisites only (signtool available, cert present) then exit.

.EXAMPLE
    .\sign-installer.ps1 -InstallerPath .\NMTKSetup.exe -Thumbprint ABCDEF1234...
    .\sign-installer.ps1 -Check
    .\sign-installer.ps1 -InstallerPath .\NMTKSetup.exe -Thumbprint ABCDEF1234... -DryRun
#>

param(
    [string]$InstallerPath = "",
    [string]$Thumbprint = $env:WINDOWS_SIGNING_THUMBPRINT,
    [string]$TimestampUrl = "http://timestamp.digicert.com",
    [switch]$DryRun,
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Find-SignTool {
    $found = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    $sdkPaths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin\x64\signtool.exe",
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe"
    )
    foreach ($p in $sdkPaths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

if ($Check) {
    $signtool = Find-SignTool
    if (-not $signtool) {
        Write-Error "signtool.exe not found. Install Windows SDK (https://developer.microsoft.com/windows/downloads/windows-sdk/)."
        exit 1
    }
    Write-Host "signtool.exe: $signtool"
    if ($Thumbprint) {
        $cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Thumbprint -eq $Thumbprint.ToUpper() }
        if (-not $cert) {
            Write-Error "Certificate with thumbprint $Thumbprint not found in CurrentUser\My store."
            exit 1
        }
        Write-Host "Certificate found: $($cert.Subject)"
    } else {
        Write-Host "No thumbprint provided — skipping certificate check."
    }
    Write-Host "Prerequisites OK."
    exit 0
}

if (-not $InstallerPath) {
    Write-Error "InstallerPath is required. Use: .\sign-installer.ps1 -InstallerPath <path>"
    exit 1
}
if (-not $Thumbprint) {
    Write-Error "Thumbprint is required (or set WINDOWS_SIGNING_THUMBPRINT env var)."
    exit 1
}
if (-not (Test-Path $InstallerPath)) {
    Write-Error "Installer not found: $InstallerPath"
    exit 1
}

$signtool = Find-SignTool
if (-not $signtool) {
    Write-Error "signtool.exe not found. Install Windows SDK."
    exit 1
}

$signArgs = @(
    "sign",
    "/sha1", $Thumbprint,
    "/fd", "sha256",
    "/tr", $TimestampUrl,
    "/td", "sha256",
    "/d", "NeuroMorphicToolKit",
    $InstallerPath
)

if ($DryRun) {
    Write-Host "[DRY RUN] Would run: $signtool $($signArgs -join ' ')"
    exit 0
}

Write-Host "Signing: $InstallerPath"
& $signtool @signArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "signtool.exe failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}
Write-Host "Signed successfully: $InstallerPath"

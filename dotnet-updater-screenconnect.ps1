<#
.SYNOPSIS
    .NET updater for ScreenConnect - Compact output and command-friendly
    
.DESCRIPTION
    This script can be run directly from ScreenConnect's command interface.
    It downloads the latest version from GitHub and executes it with filtered output.
    
    ScreenConnect One-Liner Command:
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ErrorActionPreference='Continue'; $ProgressPreference='SilentlyContinue'; $cacheBuster = Get-Date -Format 'yyyyMMddHHmmss'; New-Item -Path 'C:\temp' -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null; try { (New-Object Net.WebClient).DownloadFile(\"https://raw.githubusercontent.com/monobrau/dotnet-updater/main/dotnet-updater-screenconnect.ps1?nocache=$cacheBuster\", 'C:\temp\dotnet-updater-sc.ps1'); & 'C:\temp\dotnet-updater-sc.ps1'; exit $LASTEXITCODE } catch { Write-Host \"ERROR: $_\" -ForegroundColor Red; exit 1 }"
#>

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'

# Find the main script
$scriptPath = "C:\temp\dotnet-updater.ps1"
if (-not (Test-Path $scriptPath)) {
    $scriptPath = Join-Path $PSScriptRoot "dotnet-updater.ps1"
}

# If script doesn't exist locally, download it
if (-not (Test-Path $scriptPath)) {
    try {
        Write-Host "Downloading latest script from GitHub..." -ForegroundColor Yellow
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $scriptPath = "C:\temp\dotnet-updater.ps1"
        # Add cache-busting parameter to ensure fresh download
        $cacheBuster = Get-Date -Format 'yyyyMMddHHmmss'
        $downloadUrl = "https://raw.githubusercontent.com/monobrau/dotnet-updater/main/dotnet-updater.ps1?nocache=$cacheBuster"
        (New-Object Net.WebClient).DownloadFile($downloadUrl, $scriptPath)
        Write-Host "Download complete." -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: Could not download script: $_" -ForegroundColor Red
        exit 1
    }
}

if (-not (Test-Path $scriptPath)) {
    Write-Host "ERROR: Script not found in C:\temp or current directory" -ForegroundColor Red
    exit 1
}

Write-Host ".NET Runtime Updater" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Run the script
$result = & $scriptPath 2>&1

# Filter output to show only important lines
$result | Where-Object {
    $_ -match "\.NET" -or
    $_ -match "Status:" -or
    $_ -match "INSTALLED" -or
    $_ -match "NOT INSTALLED" -or
    $_ -match "Total updates" -or
    $_ -match "Processing" -or
    $_ -match "Installation" -or
    $_ -match "Update process completed" -or
    $_ -match "ERROR" -or
    $_ -match "WARNING" -or
    $_ -match "Runtime|Desktop|SDK"
} | ForEach-Object {
    Write-Host $_
}

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Scan completed - Exit code: $LASTEXITCODE" -ForegroundColor $(if ($LASTEXITCODE -eq 0) { "Green" } else { "Yellow" })

exit $LASTEXITCODE


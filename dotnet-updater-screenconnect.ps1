<#
.SYNOPSIS
    .NET updater for ScreenConnect - Compact output
#>

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'

# Find the main script
$scriptPath = "C:\temp\dotnet-updater.ps1"
if (-not (Test-Path $scriptPath)) {
    $scriptPath = Join-Path $PSScriptRoot "dotnet-updater.ps1"
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


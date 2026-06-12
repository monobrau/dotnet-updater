<#
.SYNOPSIS
    .NET updater for ScreenConnect - compact output and reliable exit codes
#>

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ghBase = 'https://raw.githubusercontent.com/monobrau/dotnet-updater/main'
$cacheBuster = Get-Date -Format 'yyyyMMddHHmmss'

New-Item -Path 'C:\temp' -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

$scriptPath = 'C:\temp\dotnet-updater.ps1'
try {
    (New-Object Net.WebClient).DownloadFile("$ghBase/dotnet-updater.ps1?nocache=$cacheBuster", $scriptPath)
}
catch {
    Write-Host "ERROR: Could not download script from GitHub: $_" -ForegroundColor Red
    exit 1
}

Write-Host ".NET Runtime Updater" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

$dryRun = $args -contains '-DryRun'
$scriptArgs = if ($dryRun) { @('-Quiet', '-DryRun') } else { @('-Quiet') }

& $scriptPath @scriptArgs *>&1 | Where-Object {
    $_ -match '\.NET' -or
    $_ -match 'Status:' -or
    $_ -match 'INSTALLED' -or
    $_ -match 'UPDATE REQUIRED' -or
    $_ -match 'up to date' -or
    $_ -match 'Update available' -or
    $_ -match 'Total ' -or
    $_ -match 'Processing' -or
    $_ -match 'Installation' -or
    $_ -match 'Update process completed' -or
    $_ -match 'Reboot required' -or
    $_ -match 'ERROR' -or
    $_ -match 'WARNING' -or
    $_ -match 'Runtime|Desktop|SDK|ASP\.NET' -or
    $_ -match 'DRY RUN' -or
    $_ -match 'Required by' -or
    $_ -match 'WOULD UPDATE' -or
    $_ -match 'UP TO DATE' -or
    $_ -match 'NOT INSTALLED' -or
    $_ -match 'Dry Run Summary' -or
    $_ -match 'Missing required' -or
    $_ -match 'Updates available'
} | ForEach-Object { Write-Host $_ }

$exitCode = $LASTEXITCODE
if ($null -eq $exitCode) { $exitCode = 0 }

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Scan completed - Exit code: $exitCode" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Yellow" })

exit $exitCode

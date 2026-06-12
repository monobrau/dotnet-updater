<#
.SYNOPSIS
    .NET updater for ScreenConnect - compact output and reliable exit codes
#>

param(
    [switch]$DryRun
)

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

$output = if ($DryRun) {
    & $scriptPath -Quiet -DryRun *>&1
} else {
    & $scriptPath -Quiet *>&1
}

$filterPattern = '\.NET|Status:|INSTALLED|UPDATE REQUIRED|up to date|Update available|Total |Processing|Installation|Update process completed|Reboot required|ERROR|WARNING|Runtime|Desktop|SDK|ASP\.NET|DRY RUN|Required by|WOULD UPDATE|UP TO DATE|NOT INSTALLED|Dry Run Summary|Missing required|Updates available|PENDING REBOOT'

$output | Where-Object { $_ -match $filterPattern } | ForEach-Object { Write-Host $_ }

$exitCode = $LASTEXITCODE
if ($null -eq $exitCode) { $exitCode = 0 }

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Scan completed - Exit code: $exitCode" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Yellow" })

exit $exitCode

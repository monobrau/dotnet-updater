<#
.SYNOPSIS
    .NET updater for ScreenConnect - streams live output and writes a log file
#>

param(
    [switch]$DryRun
)

if ($DryRun) {
    $env:DOTNET_UPDATER_DRYRUN = '1'
}
else {
    Remove-Item Env:DOTNET_UPDATER_DRYRUN -ErrorAction SilentlyContinue
}

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ghBase = 'https://raw.githubusercontent.com/monobrau/dotnet-updater/main'
$cacheBuster = Get-Date -Format 'yyyyMMddHHmmss'
$logPath = "C:\temp\dotnet-updater-last-run.log"

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
Write-Host "Log file: $logPath" -ForegroundColor Gray
Write-Host ""

$exitCode = 0
$noisePattern = '^\s*Attempt \d+ of \d+:|^\s*Querying Microsoft API for latest version\.\.\.|^\s*Trying releases\.json|^\s*Attempting redirect|^\s*Attempting HTML scraping'

try {
    if ($DryRun) {
        & $scriptPath -DryRun *>&1 | Tee-Object -FilePath $logPath | ForEach-Object {
            Write-Host $_.ToString()
        }
    }
    else {
        & $scriptPath *>&1 | Tee-Object -FilePath $logPath | ForEach-Object {
            $line = $_.ToString()
            if ($line -notmatch $noisePattern) {
                Write-Host $line
            }
        }
    }

    if ($null -ne $LASTEXITCODE) {
        $exitCode = $LASTEXITCODE
    }
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
}

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Scan completed - Exit code: $exitCode" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Yellow" })
Write-Host "Full log: $logPath" -ForegroundColor Gray

exit $exitCode

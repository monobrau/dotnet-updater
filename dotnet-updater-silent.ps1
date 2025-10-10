<#
.SYNOPSIS
    Silent .NET updater for ScreenConnect/RMM tools
    
.DESCRIPTION
    Runs the .NET updater with minimal output suitable for RMM tools
#>

# Suppress progress bars and verbose output
$ProgressPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'

# Capture the output
$outputPath = Join-Path $env:TEMP "dotnet_update_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

try {
    # Run the main script
    $scriptPath = Join-Path $PSScriptRoot "dotnet-updater.ps1"
    
    if (-not (Test-Path $scriptPath)) {
        $scriptPath = "C:\temp\dotnet-updater.ps1"
    }
    
    if (-not (Test-Path $scriptPath)) {
        Write-Output "ERROR: dotnet-updater.ps1 not found"
        exit 1
    }
    
    Write-Output "Starting .NET Runtime update check..."
    Write-Output "Full log: $outputPath"
    Write-Output ""
    
    # Run the script and capture output
    & $scriptPath *>&1 | Tee-Object -FilePath $outputPath
    
    $exitCode = $LASTEXITCODE
    
    Write-Output ""
    Write-Output "========================================="
    Write-Output "Update process completed"
    Write-Output "Exit Code: $exitCode"
    Write-Output "Full log saved to: $outputPath"
    Write-Output "========================================="
    
    exit $exitCode
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    Write-Output "Full log: $outputPath"
    exit 1
}


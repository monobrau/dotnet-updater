<#
.SYNOPSIS
    Cleanup old .NET installer files (EXE/MSI) from user profiles and temp directories
    
.DESCRIPTION
    Scans user profiles and temp directories for old .NET installer files and optionally removes them.
    Similar to ScreenConnect cleanup script but for .NET installers.
    
.PARAMETER AutoDelete
    Automatically delete files without prompting (use with caution)
    
.EXAMPLE
    .\dotnet-installer-cleanup.ps1
    Lists old .NET installer files and prompts for deletion
    
.EXAMPLE
    .\dotnet-installer-cleanup.ps1 -AutoDelete
    Automatically deletes old .NET installer files
#>

param(
    [switch]$AutoDelete
)

$ErrorActionPreference = 'SilentlyContinue'

# Check for auto-delete from environment variable or parameter
$AUTO = $AutoDelete -or ($env:SC_AUTODELETE -eq '1' -or $env:SC_AUTODELETE -eq 'true')

# Calculate cutoff date (August 31 of current or previous year)
$now = Get-Date
$cutYear = if ($now.Month -ge 9) { $now.Year } else { $now.Year - 1 }
$CUTOFF = Get-Date -Year $cutYear -Month 8 -Day 31 -Hour 23 -Minute 59 -Second 59

# Exclude paths (never delete these)
$EXACT_EXCLUDE = @(
    'C:\Program Files\dotnet\dotnet.exe',
    'C:\Program Files (x86)\dotnet\dotnet.exe'
)

$DIR_EXCLUDE = @(
    'C:\Program Files\dotnet\',
    'C:\Program Files (x86)\dotnet\',
    'C:\Windows\Microsoft.NET\'
)

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ".NET Installer Cleanup Tool" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Cutoff: delete files with LastWriteTime <= $($CUTOFF.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Yellow
Write-Host "Excluding (never delete):" -ForegroundColor Yellow
foreach ($excl in $EXACT_EXCLUDE) {
    Write-Host "  - $excl" -ForegroundColor Gray
}
foreach ($excl in $DIR_EXCLUDE) {
    Write-Host "  - $excl*" -ForegroundColor Gray
}
Write-Host ""

# Patterns to match .NET installer files
$patterns = @(
    'dotnet',
    'windowsdesktop-runtime',
    'aspnetcore-runtime',
    'dotnet-runtime',
    'dotnet-sdk',
    'ndp',
    'netframework'
)

# Get user profiles
$profiles = Get-ChildItem 'C:\Users' -Directory -Force | Where-Object { 
    $_.Name -notin @('All Users', 'Default', 'Default User', 'DefaultAppPool', 'Public') -and 
    $_.Name -notlike 'Default*' 
}

# Define scan locations
$roots = @()
foreach ($p in $profiles) {
    $u = $p.FullName
    $roots += @(
        "$u\Downloads",
        "$u\Desktop",
        "$u\Documents",
        "$u\AppData\Local\Temp",
        "$u\AppData\Local\Microsoft\Windows\INetCache",
        "$u\AppData\Local\Microsoft\Windows\Temporary Internet Files",
        "$u\AppData\Roaming"
    )
}

# Add system temp directories
$roots += @(
    $env:TEMP,
    "$env:WINDIR\Temp",
    "C:\temp"
)

# Filter to existing paths only
$roots = $roots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

Write-Host "Scanning $($roots.Count) locations across $($profiles.Count) user profiles..." -ForegroundColor Cyan
Write-Host ""

# Find matching files
$hits = foreach ($r in $roots) {
    Get-ChildItem -Path $r -Recurse -Force -File -Include '*.exe', '*.msi' -ErrorAction SilentlyContinue | Where-Object {
        $full = $_.FullName
        $n = $_.Name.ToLowerInvariant()
        
        # Check if filename matches any pattern
        $match = ($patterns | ForEach-Object { $n -like ('*' + $_.ToLowerInvariant() + '*') }) -contains $true
        
        # Check if file is old enough
        $old = $_.LastWriteTime -le $CUTOFF
        
        # Check if file is excluded
        $excluded = ($EXACT_EXCLUDE | Where-Object { $full -ieq $_ }) -or 
                    ($DIR_EXCLUDE | Where-Object { $full.ToLowerInvariant().StartsWith($_.ToLowerInvariant()) })
        
        $match -and $old -and (-not $excluded)
    } | Select-Object FullName, Length, LastWriteTime
}

# Sort by LastWriteTime (newest first)
$hits = $hits | Sort-Object LastWriteTime -Descending

if (-not $hits) {
    Write-Host "No old .NET installer EXE/MSI files found (with cutoff + exclusions) under user profiles." -ForegroundColor Green
    exit 0
}

# Create indexed list
$i = 0
$indexed = $hits | ForEach-Object {
    $o = [PSCustomObject]@{
        Index = $i
        SizeMB = [math]::Round($_.Length / 1MB, 2)
        LastWrite = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
        Path = $_.FullName
    }
    $script:i++
    $o
}

# Display results
Write-Host "Found $($indexed.Count) old .NET installer file(s):" -ForegroundColor Yellow
Write-Host ""
$indexed | Format-Table -AutoSize

# Calculate total size
$totalSizeMB = ($indexed | Measure-Object -Property SizeMB -Sum).Sum
Write-Host "Total size: $([math]::Round($totalSizeMB, 2)) MB" -ForegroundColor Cyan
Write-Host ""

# Auto-delete if enabled
if ($AUTO) {
    Write-Host "AUTO-DELETE enabled. Deleting (cutoff-filtered, exclusions enforced) files..." -ForegroundColor Yellow
    $ok = 0
    $fail = 0
    
    foreach ($f in $indexed) {
        if (Test-Path $f.Path) {
            Remove-Item -LiteralPath $f.Path -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path $f.Path)) {
                $ok++
                Write-Host "Deleted: $($f.Path)" -ForegroundColor Green
            }
            else {
                $fail++
                Write-Host "FAILED:  $($f.Path)" -ForegroundColor Red
            }
        }
    }
    
    Write-Host ""
    Write-Host "Done. Deleted=$ok Failed=$fail" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Yellow" })
    exit 0
}

# Interactive mode
Write-Host ""
$resp = Read-Host "Enter indexes to delete (comma-separated), A for ALL, or press Enter to cancel"

if ([string]::IsNullOrWhiteSpace($resp)) {
    Write-Host "Cancelled. No files deleted." -ForegroundColor Yellow
    exit 0
}

$toDelete = @()
if ($resp.Trim().ToUpperInvariant() -eq 'A') {
    $toDelete = $indexed
    Write-Host "Selected ALL files for deletion." -ForegroundColor Yellow
}
else {
    $nums = $resp -split '[, ]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ } | Select-Object -Unique
    $toDelete = $indexed | Where-Object { $nums -contains $_.Index }
}

if (-not $toDelete) {
    Write-Host "No valid indexes selected. No files deleted." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Deleting $($toDelete.Count) file(s)..." -ForegroundColor Yellow
$ok = 0
$fail = 0

foreach ($f in $toDelete) {
    if (Test-Path $f.Path) {
        Remove-Item -LiteralPath $f.Path -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $f.Path)) {
            $ok++
            Write-Host "Deleted: $($f.Path)" -ForegroundColor Green
        }
        else {
            $fail++
            Write-Host "FAILED:  $($f.Path)" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "Done. Deleted=$ok Failed=$fail" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Yellow" })

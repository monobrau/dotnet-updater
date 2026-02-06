# .NET Installer Cleanup Tool

A PowerShell script to find and remove old .NET installer files (EXE/MSI) from user profiles and temporary directories.

## Features

- **Smart Scanning** - Scans Downloads, Desktop, Documents, Temp folders across all user profiles
- **Cutoff Date** - Only targets files older than August 31 (current or previous year)
- **Safe Exclusions** - Never deletes actual .NET installations, only installer files
- **Interactive Mode** - Lists files and prompts for deletion
- **Auto-Delete Mode** - Can run automatically for RMM/ScreenConnect
- **Size Reporting** - Shows total disk space that can be reclaimed

## Usage

### Interactive Mode (Recommended)
```powershell
.\dotnet-installer-cleanup.ps1
```

Lists all old .NET installer files and prompts you to select which ones to delete.

### Auto-Delete Mode
```powershell
.\dotnet-installer-cleanup.ps1 -AutoDelete
```

Automatically deletes all old .NET installer files matching the criteria.

### ScreenConnect Command
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue'; $AUTO=($env:SC_AUTODELETE -eq '1' -or $env:SC_AUTODELETE -eq 'true'); $now=Get-Date; $cutYear= if($now.Month -ge 9){ $now.Year } else { $now.Year-1 }; $CUTOFF=(Get-Date -Year $cutYear -Month 8 -Day 31 -Hour 23 -Minute 59 -Second 59); $EXACT_EXCLUDE=@('C:\Program Files\dotnet\dotnet.exe','C:\Program Files (x86)\dotnet\dotnet.exe'); $DIR_EXCLUDE=@('C:\Program Files\dotnet\','C:\Program Files (x86)\dotnet\','C:\Windows\Microsoft.NET\'); Write-Host ('Cutoff: delete files with LastWriteTime <= '+$CUTOFF.ToString('yyyy-MM-dd HH:mm:ss')); $patterns=@('dotnet','windowsdesktop-runtime','aspnetcore-runtime','dotnet-runtime','dotnet-sdk','ndp','netframework'); $profiles=Get-ChildItem 'C:\Users' -Directory -Force | Where-Object { $_.Name -notin @('All Users','Default','Default User','DefaultAppPool','Public') -and $_.Name -notlike 'Default*' }; $roots=@(); foreach($p in $profiles){ $u=$p.FullName; $roots += @(\"$u\Downloads\",\"$u\Desktop\",\"$u\Documents\",\"$u\AppData\Local\Temp\",\"$u\AppData\Local\Microsoft\Windows\INetCache\",\"$u\AppData\Local\Microsoft\Windows\Temporary Internet Files\",\"$u\AppData\Roaming\") }; $roots += @($env:TEMP,\"$env:WINDIR\Temp\",'C:\temp'); $roots = $roots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique; Write-Host ('Scanning '+$roots.Count+' locations across '+$profiles.Count+' user profiles...'); $hits = foreach($r in $roots){ Get-ChildItem -Path $r -Recurse -Force -File -Include '*.exe','*.msi' -ErrorAction SilentlyContinue | Where-Object { $full=$_.FullName; $n=$_.Name.ToLowerInvariant(); $match=(($patterns | ForEach-Object { $n -like ('*'+$_.ToLowerInvariant()+'*') }) -contains $true); $old=($_.LastWriteTime -le $CUTOFF); $excluded=($EXACT_EXCLUDE | Where-Object { $full -ieq $_ }) -or ($DIR_EXCLUDE | Where-Object { $full.ToLowerInvariant().StartsWith($_.ToLowerInvariant()) }); $match -and $old -and (-not $excluded) } | Select-Object FullName,Length,LastWriteTime }; $hits = $hits | Sort-Object LastWriteTime -Descending; if(-not $hits){ Write-Host 'No old .NET installer EXE/MSI files found.'; exit 0 }; $i=0; $indexed = $hits | ForEach-Object { $o=[pscustomobject]@{Index=$i; SizeMB=[math]::Round($_.Length/1MB,2); LastWrite=$_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'); Path=$_.FullName}; $script:i++; $o }; $indexed | Format-Table -AutoSize; $totalSizeMB = ($indexed | Measure-Object -Property SizeMB -Sum).Sum; Write-Host ('Total size: '+[math]::Round($totalSizeMB,2)+' MB'); if($AUTO){ Write-Host 'AUTO-DELETE enabled. Deleting files...'; $ok=0; $fail=0; foreach($f in $indexed){ if(Test-Path $f.Path){ Remove-Item -LiteralPath $f.Path -Force -ErrorAction SilentlyContinue; if(-not (Test-Path $f.Path)){ $ok++; Write-Host ('Deleted: '+$f.Path) } else { $fail++; Write-Host ('FAILED:  '+$f.Path) } } }; Write-Host ('Done. Deleted='+$ok+' Failed='+$fail); exit 0 }; Write-Host ''; $resp = Read-Host 'Enter indexes to delete (comma-separated), A for ALL, or press Enter to cancel'; if([string]::IsNullOrWhiteSpace($resp)){ Write-Host 'Cancelled.'; exit 0 }; $toDelete = @(); if($resp.Trim().ToUpperInvariant() -eq 'A'){ $toDelete = $indexed } else { $nums = $resp -split '[, ]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ } | Select-Object -Unique; $toDelete = $indexed | Where-Object { $nums -contains $_.Index } }; if(-not $toDelete){ Write-Host 'No valid indexes.'; exit 0 }; $ok=0; $fail=0; foreach($f in $toDelete){ if(Test-Path $f.Path){ Remove-Item -LiteralPath $f.Path -Force -ErrorAction SilentlyContinue; if(-not (Test-Path $f.Path)){ $ok++; Write-Host ('Deleted: '+$f.Path) } else { $fail++; Write-Host ('FAILED:  '+$f.Path) } } }; Write-Host ('Done. Deleted='+$ok+' Failed='+$fail)"
```

## What It Does

1. **Scans** user profiles (Downloads, Desktop, Documents, Temp folders)
2. **Finds** .NET installer files (EXE/MSI) matching patterns like:
   - `dotnet-*.exe`
   - `windowsdesktop-runtime-*.exe`
   - `aspnetcore-runtime-*.exe`
   - `dotnet-sdk-*.exe`
   - `ndp*.exe` (.NET Framework installers)
3. **Filters** by cutoff date (August 31 of current/previous year)
4. **Excludes** actual .NET installations (never deletes installed runtimes)
5. **Reports** total size and file list
6. **Deletes** selected files (interactive or auto)

## Safety Features

- Never deletes files in `C:\Program Files\dotnet\`
- Never deletes files in `C:\Windows\Microsoft.NET\`
- Only targets installer files, not installed components
- Interactive mode requires confirmation
- Shows what will be deleted before deletion

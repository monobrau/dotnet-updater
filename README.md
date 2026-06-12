# .NET Runtime Updater

PowerShell script that detects installed .NET Framework and .NET (6–9) components, patches each to the latest release, and leaves all versions in place unless you opt in to removal.

## Run from GitHub (remote)

All copy-paste commands are in **[GITHUB-COMMANDS.txt](GITHUB-COMMANDS.txt)**.

| Task | File section |
|---|---|
| ScreenConnect update (recommended) | `SCREENCONNECT — UPDATE` |
| ScreenConnect dry run | `SCREENCONNECT — DRY RUN` |
| Full output update | `CMD / POWERSHELL — UPDATE` |
| Full output dry run | `CMD / POWERSHELL — DRY RUN` |

Quick picks:

**ScreenConnect update:**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Continue';$ProgressPreference='SilentlyContinue';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;$t=Get-Date -Format 'yyyyMMddHHmmss';New-Item -Path C:\temp -ItemType Directory -Force -ErrorAction SilentlyContinue|Out-Null;try{(New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/monobrau/dotnet-updater/main/dotnet-updater-screenconnect.ps1?nocache='+$t,'C:\temp\dotnet-updater-sc.ps1');& C:\temp\dotnet-updater-sc.ps1;exit $LASTEXITCODE}catch{Write-Host 'ERROR:' $_.Exception.Message -ForegroundColor Red;exit 1}"
```

**ScreenConnect dry run** — use `#!ps` block in [GITHUB-COMMANDS.txt](GITHUB-COMMANDS.txt), or this cmd one-liner (paste **one line only**):
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$env:DOTNET_UPDATER_DRYRUN='1';$ErrorActionPreference='Continue';$ProgressPreference='SilentlyContinue';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;$t=Get-Date -Format 'yyyyMMddHHmmss';New-Item -Path C:\temp -ItemType Directory -Force -ErrorAction SilentlyContinue|Out-Null;try{(New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/monobrau/dotnet-updater/main/dotnet-updater.ps1?nocache='+$t,'C:\temp\dotnet-updater.ps1');& C:\temp\dotnet-updater.ps1 -DryRun;exit $LASTEXITCODE}catch{Write-Host 'ERROR:' $_.Exception.Message -ForegroundColor Red;exit 1}"
```

- Run installs as **admin / SYSTEM**; `-DryRun` works without elevation.
- In **cmd**, paste only the single command line — never paste script output back (cmd will try to run each line).
- Prefer ScreenConnect **`#!ps`** blocks over raw cmd for PowerShell scripts.
- Allow **5–10 minutes** on update runs.
- Wrapper always re-downloads the latest script from GitHub (no stale cache).

## Run locally

```powershell
.\dotnet-updater.ps1              # update (removes nothing)
.\dotnet-updater.ps1 -DryRun       # preview only
.\dotnet-updater.ps1 -Quiet        # minimal output
.\dotnet-updater.ps1 -Verbose      # diagnostics
.\dotnet-updater.ps1 -RemoveOldVersions   # remove unused older majors
```

## What it does

- Patches each **installed** major version (6, 7, 8, 9) to its latest release
- Updates **Desktop**, **ASP.NET Core**, **Runtime**, and **SDK** independently
- Upgrades **.NET Framework** to the newest supported release (e.g. 4.8 → 4.8.1)
- `-DryRun`: scans apps for required versions, previews updates — no installs
- `-RemoveOldVersions`: removes older majors only when apps no longer reference them

## Requirements

- Windows PowerShell 5.1+
- Administrator privileges (for installs)
- Internet access
- Windows 10 1607+ / Server 2016+ for .NET 7+

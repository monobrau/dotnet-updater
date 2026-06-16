# .NET Runtime Updater

PowerShell script that detects installed .NET Framework and .NET (6–9) components, patches each to the latest release, and leaves all versions in place unless you opt in to removal.

Repo: **https://github.com/monobrau/dotnet-updater**

## ScreenConnect (recommended)

Paste into ScreenConnect **Commands** as a `#!ps` block. Scripts download from GitHub at run time — nothing to deploy first.

### Dry run (preview — no installs)

Run this first on each machine. No admin required.

```powershell
#!ps
#maxlength=200000
#timeout=300000
$env:DOTNET_UPDATER_DRYRUN = '1'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
New-Item -Path "C:\temp" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
$t = Get-Date -Format 'yyyyMMddHHmmss'
(New-Object Net.WebClient).DownloadFile("https://raw.githubusercontent.com/monobrau/dotnet-updater/main/dotnet-updater.ps1?nocache=$t", "C:\temp\dotnet-updater.ps1")
& "C:\temp\dotnet-updater.ps1" -DryRun
```

Look for `Mode: DRY RUN` and `Updates available: N` in the summary. No `Downloading` or `Installing` lines.

### Update (install patches)

Run as **admin / SYSTEM** after dry run looks good. Allow **5–10 minutes**.

```powershell
#!ps
#maxlength=200000
#timeout=600000
Remove-Item Env:DOTNET_UPDATER_DRYRUN -ErrorAction SilentlyContinue
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
New-Item -Path "C:\temp" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
$t = Get-Date -Format 'yyyyMMddHHmmss'
(New-Object Net.WebClient).DownloadFile("https://raw.githubusercontent.com/monobrau/dotnet-updater/main/dotnet-updater-screenconnect.ps1?nocache=$t", "C:\temp\dotnet-updater-sc.ps1")
& "C:\temp\dotnet-updater-sc.ps1"
```

Full log: `C:\temp\dotnet-updater-last-run.log`

### Tips

- **Dry run first, update second** — dry run uses `$env:DOTNET_UPDATER_DRYRUN` or `-DryRun`; update clears that and must not include it.
- **Reboot** if dry run shows `PENDING REBOOT` for .NET Framework before running update again.
- **Missing runtimes** (e.g. apps need .NET 6 but it is not installed) are reported in dry run but not installed automatically — install those manually.
- More commands (cmd one-liners, remove-old): **[GITHUB-COMMANDS.txt](GITHUB-COMMANDS.txt)**

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

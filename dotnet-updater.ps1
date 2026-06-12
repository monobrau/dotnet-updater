<#
.SYNOPSIS
    Comprehensive updater for all .NET Framework and .NET versions.

.DESCRIPTION
    This comprehensive script scans for and updates ALL major .NET versions:
    - .NET Framework 4.6.2, 4.7, 4.7.1, 4.7.2, 4.8, 4.8.1
    - .NET 6.0, 7.0, 8.0, 9.0 (each receives patch updates within its own major branch)

    The script runs completely silently with no user interaction required.
    It intelligently compares installed versions with target versions and skips updates
    for versions that are already up to date, saving time and bandwidth.

.NOTES
    File Name: dotnet-updater.ps1
    Run this script with administrative privileges.
    All URLs point to official Microsoft downloads.

    Version Checking:
    - .NET Framework: Detects installed version and updates to the latest available Framework version
    - .NET (Core/5+): Downloads and checks latest available versions
    - Automatically detects if downloaded installer is newer than installed version
    - Skips installation if current version is already up to date
    - Avoids unnecessary downloads when versions are already current

    Security Features:
    - Network retry logic with exponential backoff (3 attempts)
    - File size validation (minimum 1 MB)
    - Digital signature verification (Microsoft signed)
    - File type validation (.exe only)

    Update Behavior:
    - .NET Framework: Updates to the highest available Framework version (e.g., 4.8 → 4.8.1)
    - .NET 6/7/8/9: Each installed major version is patched to its latest release
    - Desktop, ASP.NET Core, Runtime, and SDK components are updated independently

    Runtime Type Detection:
    - Desktop installations receive Desktop Runtime (includes WPF, WinForms)
    - Server installations (ASP.NET Core only) receive base Runtime
    - Prevents unnecessary Desktop components on servers

    Verbosity:
    - Run with -Verbose for detailed diagnostic output
    - Run with -DryRun to scan app requirements and preview updates without installing
    - Default output shows only essential information
#>

param(
    [switch]$RemoveOldVersions,
    [switch]$Quiet,
    [switch]$DryRun
)

function Write-Status {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )
    if (-not $Quiet) {
        Write-Host $Message -ForegroundColor $Color
    }
}

# Enforce TLS 1.2 for downloads
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ".NET Framework & .NET Updater" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Detect OS version for compatibility checking
$osInfo = Get-CimInstance Win32_OperatingSystem
$osVersion = [System.Version]$osInfo.Version
$osName = $osInfo.Caption
$osBuildNumber = $osInfo.BuildNumber

Write-Host "Detected OS: $osName" -ForegroundColor Gray
Write-Host "OS Version: $($osVersion.Major).$($osVersion.Minor) Build $osBuildNumber" -ForegroundColor Gray
Write-Host ""

# Determine OS compatibility
$script:SupportsModernDotNet = $false
$script:SupportsDotNet481 = $false

# Windows 10 build 14393 (1607) or later, or Windows 11, or Server 2016+
if ($osVersion.Major -ge 10) {
    if ($osVersion.Build -ge 14393) {
        $script:SupportsModernDotNet = $true
        $script:SupportsDotNet481 = $true
    }
    elseif ($osVersion.Build -ge 10240) {
        # Windows 10 RTM (10240) to 1511 - supports .NET 6 but not 7+
        $script:SupportsModernDotNet = $false  # Will check per-version
        $script:SupportsDotNet481 = $false
    }
}
# Windows Server 2012 R2
elseif ($osVersion.Major -eq 6 -and $osVersion.Minor -eq 3) {
    $script:SupportsModernDotNet = $true  # Supports .NET 6-8
    $script:SupportsDotNet481 = $false
}
# Windows 8.1 / Server 2012 R2
elseif ($osVersion.Major -eq 6 -and $osVersion.Minor -ge 2) {
    $script:SupportsModernDotNet = $false  # Limited support
    $script:SupportsDotNet481 = $false
}
# Windows 7 SP1 / Server 2008 R2
elseif ($osVersion.Major -eq 6 -and $osVersion.Minor -eq 1) {
    $script:SupportsModernDotNet = $false  # Can do .NET 6 only
    $script:SupportsDotNet481 = $false
}

# Helper function to check if specific .NET version is supported
function Test-DotNetVersionSupported {
    param(
        [string]$DotNetMajorVersion
    )
    
    $majorVer = [int]$DotNetMajorVersion
    
    # .NET 6 - Supports Windows 7 SP1+, Server 2012+
    if ($majorVer -eq 6) {
        return ($osVersion.Major -ge 6 -and $osVersion.Minor -ge 1)
    }
    
    # .NET 7, 8, 9 - Requires Windows 10 1607+ or Server 2012+
    if ($majorVer -ge 7) {
        if ($osVersion.Major -ge 10 -and $osVersion.Build -ge 14393) {
            return $true
        }
        if ($osVersion.Major -eq 6 -and $osVersion.Minor -ge 3) {
            return $true  # Server 2012 R2
        }
        return $false
    }
    
    return $true
}

Write-Host ""

# Define all .NET versions and their download URLs
$DotNetVersions = @{
    "Framework-4.6.2" = @{
        DisplayName = "Microsoft \.NET Framework 4\.6\.2"
        RegistryPath = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
        RegistryValue = "Release"
        MinRelease = 394802
        TargetVersion = "4.6.2"
        IsFramework = $true
        URLs = @{
            Offline = "https://download.microsoft.com/download/F/9/4/F942F07D-F26F-4F30-B4E3-EBD54FABA377/NDP462-KB3151800-x86-x64-AllOS-ENU.exe"
            Web = "https://download.microsoft.com/download/F/9/4/F942F07D-F26F-4F30-B4E3-EBD54FABA377/NDP462-KB3151802-Web.exe"
        }
    }
    "Framework-4.7" = @{
        DisplayName = "Microsoft \.NET Framework 4\.7"
        RegistryPath = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
        RegistryValue = "Release"
        MinRelease = 460798
        TargetVersion = "4.7"
        IsFramework = $true
        URLs = @{
            Offline = "https://download.microsoft.com/download/D/D/3/DD35CC25-6E9C-484B-A746-C5BE0C923290/NDP47-KB3186497-x86-x64-AllOS-ENU.exe"
            Web = "https://download.microsoft.com/download/A/E/A/AEAE0F3F-96E9-4711-AADA-5E35EF902306/NDP47-KB3186500-Web.exe"
        }
    }
    "Framework-4.7.1" = @{
        DisplayName = "Microsoft \.NET Framework 4\.7\.1"
        RegistryPath = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
        RegistryValue = "Release"
        MinRelease = 461308
        TargetVersion = "4.7.1"
        IsFramework = $true
        URLs = @{
            Offline = "https://download.microsoft.com/download/9/E/6/9E63300C-0941-4B45-A0EC-0008F96DD480/NDP471-KB4033342-x86-x64-AllOS-ENU.exe"
            Web = "https://download.microsoft.com/download/9/E/6/9E63300C-0941-4B45-A0EC-0008F96DD480/NDP471-KB4033344-Web.exe"
        }
    }
    "Framework-4.7.2" = @{
        DisplayName = "Microsoft \.NET Framework 4\.7\.2"
        RegistryPath = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
        RegistryValue = "Release"
        MinRelease = 461808
        TargetVersion = "4.7.2"
        IsFramework = $true
        URLs = @{
            Offline = "https://download.microsoft.com/download/6/E/4/6E48E8AB-DC00-419E-9704-06DD46E5F81D/NDP472-KB4054530-x86-x64-AllOS-ENU.exe"
            Web = "https://download.microsoft.com/download/6/E/4/6E48E8AB-DC00-419E-9704-06DD46E5F81D/NDP472-KB4054531-Web.exe"
        }
    }
    "Framework-4.8" = @{
        DisplayName = "Microsoft \.NET Framework 4\.8"
        RegistryPath = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
        RegistryValue = "Release"
        MinRelease = 528040
        TargetVersion = "4.8"
        IsFramework = $true
        URLs = @{
            Offline = "https://download.microsoft.com/download/7/D/1/7D15524C-8F8C-4F9C-A580-A6A935E2F8F1/NDP48-x86-x64-AllOS-ENU.exe"
            Web = "https://download.microsoft.com/download/7/D/1/7D15524C-8F8C-4F9C-A580-A6A935E2F8F1/NDP48-Web.exe"
        }
    }
    "Framework-4.8.1" = @{
        DisplayName = "Microsoft \.NET Framework 4\.8\.1"
        RegistryPath = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
        RegistryValue = "Release"
        MinRelease = 533320
        TargetVersion = "4.8.1"
        IsFramework = $true
        URLs = @{
            Offline = "https://go.microsoft.com/fwlink/?linkid=2203306"
            Web = "https://go.microsoft.com/fwlink/?linkid=2203305"
        }
    }
    "NET-6.0" = @{
        DisplayName = "Microsoft\.NET\.Runtime\.6"
        TargetVersion = $null
        IsFramework = $false
        IsLTS = $true
        AutoUpdate = $true
        URLs = @{
            Runtime = "https://dotnet.microsoft.com/en-us/download/dotnet/6.0"
            Desktop = "https://dotnet.microsoft.com/en-us/download/dotnet/6.0"
            SDK = "https://dotnet.microsoft.com/en-us/download/dotnet/6.0"
        }
    }
    "NET-7.0" = @{
        DisplayName = "Microsoft\.NET\.Runtime\.7"
        TargetVersion = $null
        IsFramework = $false
        IsLTS = $false
        AutoUpdate = $true
        URLs = @{
            Runtime = "https://dotnet.microsoft.com/en-us/download/dotnet/7.0"
            Desktop = "https://dotnet.microsoft.com/en-us/download/dotnet/7.0"
            SDK = "https://dotnet.microsoft.com/en-us/download/dotnet/7.0"
        }
    }
    "NET-8.0" = @{
        DisplayName = "Microsoft\.NET\.Runtime\.8"
        TargetVersion = $null
        IsFramework = $false
        IsLTS = $true
        AutoUpdate = $true
        URLs = @{
            Runtime = "https://dotnet.microsoft.com/en-us/download/dotnet/8.0"
            Desktop = "https://dotnet.microsoft.com/en-us/download/dotnet/8.0"
            SDK = "https://dotnet.microsoft.com/en-us/download/dotnet/8.0"
        }
    }
    "NET-9.0" = @{
        DisplayName = "Microsoft\.NET\.Runtime\.9"
        TargetVersion = $null
        IsFramework = $false
        IsLTS = $false
        AutoUpdate = $true
        URLs = @{
            Runtime = "https://dotnet.microsoft.com/en-us/download/dotnet/9.0"
            Desktop = "https://dotnet.microsoft.com/en-us/download/dotnet/9.0"
            SDK = "https://dotnet.microsoft.com/en-us/download/dotnet/9.0"
        }
    }
}

function Test-SystemRebootPending {
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        return $true
    }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        return $true
    }
    try {
        $pending = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop
        if ($pending.PendingFileRenameOperations) {
            return $true
        }
    }
    catch {
        Write-Verbose "Could not read PendingFileRenameOperations: $_"
    }
    return $false
}

# Function to get .NET Framework version from registry
function Get-DotNetFrameworkVersion {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RegistryPath,
        [Parameter(Mandatory=$true)]
        [string]$RegistryValue
    )
    
    try {
        if (Test-Path $RegistryPath) {
            $release = Get-ItemProperty -Path $RegistryPath -Name $RegistryValue -ErrorAction SilentlyContinue
            if ($release) {
                return $release.$RegistryValue
            }
        }
    }
    catch {
        Write-Verbose "Error reading registry: $_"
    }

    return $null
}

# Function to check installed .NET versions using dotnet command
# Helper function to add cache-busting parameter to URLs
function Add-CacheBuster {
    param(
        [string]$Url
    )
    
    $separator = if ($Url -match '\?') { '&' } else { '?' }
    $cacheBuster = Get-Date -Format 'yyyyMMddHHmmss'
    return "$Url${separator}nocache=$cacheBuster"
}

function Get-InstalledDotNetVersions {
    try {
        # Try to find dotnet.exe - check PATH first, then common installation locations
        $dotnetExe = $null
        
        # First, try PATH
        $dotnetPath = Get-Command dotnet -ErrorAction SilentlyContinue
        if ($dotnetPath) {
            $dotnetExe = $dotnetPath.Source
            Write-Verbose "Found dotnet in PATH: $dotnetExe"
        }
        else {
            # Try common installation paths
            $commonPaths = @(
                "${env:ProgramFiles}\dotnet\dotnet.exe",
                "${env:ProgramFiles(x86)}\dotnet\dotnet.exe",
                "$env:LOCALAPPDATA\Microsoft\dotnet\dotnet.exe"
            )
            
            foreach ($path in $commonPaths) {
                if (Test-Path $path) {
                    $dotnetExe = $path
                    Write-Verbose "Found dotnet at: $dotnetExe"
                    break
                }
            }
        }
        
        if (-not $dotnetExe) {
            Write-Verbose "dotnet.exe not found in PATH or common locations"
            Write-Verbose "Checked PATH: $(if ($dotnetPath) { 'Found' } else { 'Not found' })"
            foreach ($path in $commonPaths) {
                Write-Verbose "  $path : $(if (Test-Path $path) { 'Found' } else { 'Not found' })"
            }
            return @{
                Runtimes = @()
                SDKs = @()
                Available = $false
            }
        }
        
        # Get runtimes and SDKs, capturing both stdout and stderr
        Write-Verbose "Using dotnet.exe at: $dotnetExe"
        $runtimesOutput = & $dotnetExe --list-runtimes 2>&1
        $sdksOutput = & $dotnetExe --list-sdks 2>&1
        
        # Filter out error messages and get only successful output
        # Convert all output to strings first, then filter
        $runtimes = @()
        foreach ($line in $runtimesOutput) {
            $lineStr = $line.ToString()
            if ($lineStr -match "Microsoft\.") {
                $runtimes += $lineStr
            }
        }
        
        $sdks = @()
        foreach ($line in $sdksOutput) {
            $lineStr = $line.ToString()
            if ($lineStr -match "^\d+\.\d+\.\d+") {
                $sdks += $lineStr
            }
        }
        
        Write-Verbose "Found $($runtimes.Count) runtimes and $($sdks.Count) SDKs"
        if ($runtimes.Count -gt 0) {
            Write-Verbose "Sample runtimes: $($runtimes[0..([Math]::Min(2, $runtimes.Count-1))] -join ', ')"
        }
        else {
            Write-Verbose "No runtimes found after filtering."
            Write-Verbose "Raw dotnet --list-runtimes output ($($runtimesOutput.Count) lines):"
            $runtimesOutput | ForEach-Object { Write-Verbose "  $_" }
        }
        if ($sdks.Count -gt 0) {
            Write-Verbose "Sample SDKs: $($sdks[0..([Math]::Min(2, $sdks.Count-1))] -join ', ')"
        }
        else {
            Write-Verbose "No SDKs found. Raw output: $($sdksOutput -join ' | ')"
        }
        
        return @{
            Runtimes = $runtimes
            SDKs = $sdks
            Available = $true
        }
    }
    catch {
        Write-Verbose "Error getting .NET versions: $_"
        return @{
            Runtimes = @()
            SDKs = @()
            Available = $false
        }
    }
}

# Function to find .NET uninstall entries from registry (fast; avoids Win32_Product)
function Get-DotNetUninstallEntries {
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($path in $registryPaths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match 'Microsoft (\.NET|ASP\.NET)' } |
            Select-Object DisplayName, UninstallString, QuietUninstallString, PSChildName
    }
}

$script:RequiredDotNetCache = $null

function Get-RequiredDotNetVersions {
    if ($script:RequiredDotNetCache) {
        return $script:RequiredDotNetCache
    }

    $searchRoots = @(
        ${env:ProgramFiles},
        ${env:ProgramFiles(x86)},
        'C:\inetpub\wwwroot'
    ) | Where-Object { $_ -and (Test-Path $_) }

    $majors = @{}
    $references = @()

    foreach ($root in $searchRoots) {
        $configFiles = Get-ChildItem -Path $root -Filter '*.runtimeconfig.json' -Recurse -ErrorAction SilentlyContinue -Depth 6 |
            Select-Object -First 500

        foreach ($configFile in $configFiles) {
            $majorVersion = $null
            $frameworkName = $null
            $frameworkVersion = $null

            try {
                $config = Get-Content -Path $configFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                $frameworks = @()
                if ($config.runtimeOptions.framework) {
                    $frameworks += $config.runtimeOptions.framework
                }
                if ($config.runtimeOptions.frameworks) {
                    $frameworks += @($config.runtimeOptions.frameworks)
                }

                foreach ($framework in $frameworks) {
                    $frameworkName = $framework.name
                    $frameworkVersion = $framework.version
                    if ($frameworkVersion -match '^(\d+)\.') {
                        $majorVersion = [int]$matches[1]
                        if ($majorVersion -ge 5) {
                            if (-not $majors.ContainsKey($majorVersion)) {
                                $majors[$majorVersion] = @()
                            }
                            $ref = [PSCustomObject]@{
                                MajorVersion = $majorVersion
                                Framework = $frameworkName
                                Version = $frameworkVersion
                                Path = $configFile.FullName
                                Source = 'runtimeconfig.json'
                            }
                            $majors[$majorVersion] += $ref
                            $references += $ref
                        }
                    }
                }
            }
            catch {
                $content = Get-Content -Path $configFile.FullName -Raw -ErrorAction SilentlyContinue
                if ($content -match 'Microsoft\.(NETCore|AspNetCore|WindowsDesktop)\.App.*?(\d+)\.\d+') {
                    $majorVersion = [int]$matches[2]
                    if ($majorVersion -ge 5) {
                        if (-not $majors.ContainsKey($majorVersion)) {
                            $majors[$majorVersion] = @()
                        }
                        $ref = [PSCustomObject]@{
                            MajorVersion = $majorVersion
                            Framework = $matches[1]
                            Version = $null
                            Path = $configFile.FullName
                            Source = 'runtimeconfig.json'
                        }
                        $majors[$majorVersion] += $ref
                        $references += $ref
                    }
                }
            }
        }

        $depsFiles = Get-ChildItem -Path $root -Filter '*.deps.json' -Recurse -ErrorAction SilentlyContinue -Depth 6 |
            Select-Object -First 300

        foreach ($depsFile in $depsFiles) {
            $content = Get-Content -Path $depsFile.FullName -Raw -ErrorAction SilentlyContinue
            if (-not $content) { continue }

            if ($content -match '"targetFramework"\s*:\s*"(net\d+\.\d+)"') {
                $tfm = $matches[1]
                if ($tfm -match '^net(\d+)\.') {
                    $majorVersion = [int]$matches[1]
                    if ($majorVersion -ge 5) {
                        if (-not $majors.ContainsKey($majorVersion)) {
                            $majors[$majorVersion] = @()
                        }
                        $ref = [PSCustomObject]@{
                            MajorVersion = $majorVersion
                            Framework = $tfm
                            Version = $null
                            Path = $depsFile.FullName
                            Source = 'deps.json'
                        }
                        $majors[$majorVersion] += $ref
                        $references += $ref
                    }
                }
            }
        }
    }

    $script:RequiredDotNetCache = [PSCustomObject]@{
        Majors = $majors
        References = $references
    }
    return $script:RequiredDotNetCache
}

function Test-DotNetVersionInUse {
    param(
        [int]$MajorVersion
    )

    $required = Get-RequiredDotNetVersions
    return $required.Majors.ContainsKey($MajorVersion)
}

function Get-InstalledDotNetComponents {
    param(
        [hashtable]$Installed
    )

    $components = @()

    $desktopLine = @($Installed.Desktop) | Select-Object -First 1
    if ($desktopLine -match '(\d+\.\d+\.\d+)') {
        $components += [PSCustomObject]@{ Type = 'Desktop'; CurrentVersion = $matches[1]; Line = $desktopLine }
    }

    $aspCoreLine = @($Installed.AspCore) | Select-Object -First 1
    if ($aspCoreLine -match '(\d+\.\d+\.\d+)') {
        $components += [PSCustomObject]@{ Type = 'AspNetCore'; CurrentVersion = $matches[1]; Line = $aspCoreLine }
    }

    if (-not $Installed.Desktop) {
        $runtimeLine = @($Installed.Runtime) | Select-Object -First 1
        if ($runtimeLine -match '(\d+\.\d+\.\d+)') {
            $components += [PSCustomObject]@{ Type = 'Runtime'; CurrentVersion = $matches[1]; Line = $runtimeLine }
        }
    }

    foreach ($sdkLine in @($Installed.SDK)) {
        if ($sdkLine -match '^(\d+\.\d+\.\d+)') {
            $components += [PSCustomObject]@{ Type = 'SDK'; CurrentVersion = $matches[1]; Line = $sdkLine }
            break
        }
    }

    return $components
}

function Test-DotNetComponentUpdate {
    param(
        [int]$MajorVersion,
        [string]$Component,
        [string]$CurrentVersion
    )

    $componentLabels = @{
        Desktop    = 'Desktop Runtime'
        AspNetCore = 'ASP.NET Core Runtime'
        Runtime    = 'Runtime'
        SDK        = 'SDK'
    }
    $displayName = $componentLabels[$Component]

    if (-not (Test-DotNetVersionSupported -DotNetMajorVersion $MajorVersion)) {
        return [PSCustomObject]@{
            Status = 'Unsupported'
            MajorVersion = $MajorVersion
            Component = $Component
            DisplayName = $displayName
            CurrentVersion = $CurrentVersion
            LatestVersion = $null
        }
    }

    $latestVersion = Get-DotNetLatestVersion -MajorVersion $MajorVersion
    if (-not $latestVersion) {
        return [PSCustomObject]@{
            Status = 'Unknown'
            MajorVersion = $MajorVersion
            Component = $Component
            DisplayName = $displayName
            CurrentVersion = $CurrentVersion
            LatestVersion = $null
        }
    }

    $status = if (Compare-Version -CurrentVersion $CurrentVersion -TargetVersion $latestVersion) {
        'UpToDate'
    } else {
        'WouldUpdate'
    }

    return [PSCustomObject]@{
        Status = $status
        MajorVersion = $MajorVersion
        Component = $Component
        DisplayName = $displayName
        CurrentVersion = $CurrentVersion
        LatestVersion = $latestVersion
    }
}

function Get-InstalledDotNetMajors {
    param(
        [hashtable]$DotNetInfo
    )

    $majors = @{}
    if (-not $DotNetInfo.Available) {
        return $majors
    }

    foreach ($runtime in $DotNetInfo.Runtimes) {
        if ($runtime -match 'Microsoft\.(NETCore|WindowsDesktop|AspNetCore)\.App (\d+)\.') {
            $majors[[int]$matches[2]] = $true
        }
    }
    foreach ($sdk in $DotNetInfo.SDKs) {
        if ($sdk -match '^(\d+)\.') {
            $majors[[int]$matches[1]] = $true
        }
    }
    return $majors
}

function Invoke-DryRunReport {
    param(
        [hashtable]$InstalledVersions,
        [hashtable]$DotNetVersionsTable,
        [hashtable]$DotNetInfo
    )

    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "DRY RUN - No downloads or installs" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""

    $required = Get-RequiredDotNetVersions
    $installedMajors = Get-InstalledDotNetMajors -DotNetInfo $DotNetInfo
    $wouldUpdate = @()
    $upToDate = @()
    $unsupported = @()

    Write-Host "Required by deployed apps:" -ForegroundColor Yellow
    if ($required.Majors.Count -eq 0) {
        Write-Host "  None detected (scanned Program Files, Program Files (x86), inetpub)" -ForegroundColor Gray
    }
    else {
        foreach ($major in ($required.Majors.Keys | Sort-Object)) {
            $appCount = $required.Majors[$major].Count
            $installed = if ($installedMajors.ContainsKey($major)) { 'installed' } else { 'NOT INSTALLED' }
            $color = if ($installedMajors.ContainsKey($major)) { 'Green' } else { 'Red' }
            Write-Host "  .NET $major - $appCount app reference(s) - $installed" -ForegroundColor $color
            if ($VerbosePreference -eq 'Continue') {
                foreach ($ref in ($required.Majors[$major] | Select-Object -First 5)) {
                    Write-Verbose "    $($ref.Path) [$($ref.Source)]"
                }
            }
        }
    }
    Write-Host ""

    Write-Host "Installed components - update check:" -ForegroundColor Yellow
    if ($InstalledVersions.Count -eq 0) {
        Write-Host "  No .NET installations detected on this machine." -ForegroundColor Gray
    }

    foreach ($version in $InstalledVersions.Keys | Sort-Object) {
        $installed = $InstalledVersions[$version]

        if ($installed.IsFramework) {
            if ($installed.PendingReboot) {
                Write-Host "  PENDING REBOOT: .NET Framework $($installed.TargetVersion) (restart required to finish)" -ForegroundColor Yellow
            }
            elseif ($installed.NeedsUpdate) {
                $targetInfo = $DotNetVersionsTable[$version]
                if ($targetInfo.TargetVersion -eq '4.8.1' -and -not $script:SupportsDotNet481) {
                    $unsupported += [PSCustomObject]@{
                        Name = ".NET Framework $($installed.CurrentVersion) -> $($installed.TargetVersion)"
                        Reason = 'OS does not support .NET Framework 4.8.1'
                    }
                }
                else {
                    $wouldUpdate += [PSCustomObject]@{
                        Name = ".NET Framework $($installed.CurrentVersion) -> $($installed.TargetVersion)"
                        CurrentVersion = $installed.CurrentVersion
                        LatestVersion = $installed.TargetVersion
                    }
                    Write-Host "  WOULD UPDATE: .NET Framework $($installed.CurrentVersion) -> $($installed.TargetVersion)" -ForegroundColor Yellow
                }
            }
            else {
                $upToDate += ".NET Framework $($installed.CurrentVersion)"
                Write-Host "  UP TO DATE: .NET Framework $($installed.CurrentVersion)" -ForegroundColor Cyan
            }
            continue
        }

        $majorVersion = [int]$version.Split('-')[1].Split('.')[0]
        foreach ($component in Get-InstalledDotNetComponents -Installed $installed) {
            $result = Test-DotNetComponentUpdate -MajorVersion $majorVersion -Component $component.Type -CurrentVersion $component.CurrentVersion

            switch ($result.Status) {
                'WouldUpdate' {
                    $wouldUpdate += $result
                    Write-Host "  WOULD UPDATE: .NET $majorVersion $($result.DisplayName) $($result.CurrentVersion) -> $($result.LatestVersion)" -ForegroundColor Yellow
                }
                'UpToDate' {
                    $upToDate += $result
                    Write-Host "  UP TO DATE: .NET $majorVersion $($result.DisplayName) $($result.CurrentVersion)" -ForegroundColor Cyan
                }
                'Unsupported' {
                    $unsupported += $result
                    Write-Host "  UNSUPPORTED: .NET $majorVersion $($result.DisplayName) on this OS" -ForegroundColor DarkYellow
                }
                default {
                    Write-Host "  UNKNOWN: .NET $majorVersion $($result.DisplayName) - could not query latest version" -ForegroundColor DarkYellow
                }
            }
        }
    }

    if ($RemoveOldVersions) {
        Write-Host ""
        Write-Host "Would remove (with -RemoveOldVersions):" -ForegroundColor Yellow
        $versionsToRemove = @()
        $majorsInUse = $installedMajors.Clone()
        $installedMajorList = $majorsInUse.Keys | Sort-Object
        $newestMajor = if ($installedMajorList) { ($installedMajorList | Measure-Object -Maximum).Maximum } else { 0 }

        if ($DotNetInfo.Available -and $newestMajor -gt 0) {
            foreach ($runtime in $DotNetInfo.Runtimes) {
                $candidates = @(
                    @{ Pattern = 'Microsoft\.NETCore\.App (\d+\.\d+\.\d+)'; Type = 'Runtime' }
                    @{ Pattern = 'Microsoft\.WindowsDesktop\.App (\d+\.\d+\.\d+)'; Type = 'Desktop' }
                    @{ Pattern = 'Microsoft\.AspNetCore\.App (\d+\.\d+\.\d+)'; Type = 'AspCore' }
                )
                foreach ($candidate in $candidates) {
                    if ($runtime -match $candidate.Pattern) {
                        $ver = $matches[1]
                        $major = [int]$ver.Split('.')[0]
                        if ($major -lt $newestMajor -and -not (Test-DotNetVersionInUse -MajorVersion $major)) {
                            $versionsToRemove += "$($candidate.Type) $ver"
                        }
                    }
                }
            }
        }

        if ($versionsToRemove.Count -gt 0) {
            foreach ($item in $versionsToRemove) {
                Write-Host "  WOULD REMOVE: $item" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "  Nothing to remove" -ForegroundColor Gray
        }
    }

    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Dry Run Summary" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "  App-required majors:     $(if ($required.Majors.Count) { ($required.Majors.Keys | Sort-Object) -join ', ' } else { 'none detected' })" -ForegroundColor Gray
    Write-Host "  Installed majors:        $(if ($installedMajors.Count) { ($installedMajors.Keys | Sort-Object) -join ', ' } else { 'none' })" -ForegroundColor Gray
    $missingRequired = @($required.Majors.Keys | Where-Object { -not $installedMajors.ContainsKey($_) } | Sort-Object)
    Write-Host "  Missing required:        $(if ($missingRequired.Count) { $missingRequired -join ', ' } else { 'none' })" -ForegroundColor $(if ($missingRequired.Count) { 'Red' } else { 'Gray' })
    Write-Host "  Updates available:       $($wouldUpdate.Count)" -ForegroundColor $(if ($wouldUpdate.Count) { 'Yellow' } else { 'Green' })
    Write-Host "  Already up to date:     $($upToDate.Count)" -ForegroundColor Gray
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Run without -DryRun to apply updates." -ForegroundColor Cyan
}

# Function to uninstall a .NET component via registry uninstall string
function Uninstall-DotNetVersion {
    param(
        [string]$Version,
        [string]$Type
    )

    $typePatterns = @{
        Runtime  = "\.NET (Runtime|Host) - $([regex]::Escape($Version))"
        Desktop  = "\.NET Desktop Runtime - $([regex]::Escape($Version))"
        AspCore  = "ASP\.NET Core .+ Runtime - $([regex]::Escape($Version))"
        SDK      = "\.NET SDK - $([regex]::Escape($Version))"
    }

    $pattern = $typePatterns[$Type]
    if (-not $pattern) {
        Write-Warning "  Unknown component type for uninstall: $Type"
        return $false
    }

    try {
        $entries = Get-DotNetUninstallEntries | Where-Object { $_.DisplayName -match $pattern }
        if (-not $entries) {
            Write-Status "  No uninstall entry found for $Type $Version" Yellow
            return $false
        }

        $removed = $false
        foreach ($entry in $entries) {
            $uninstallCmd = if ($entry.QuietUninstallString) { $entry.QuietUninstallString } else { $entry.UninstallString }
            if (-not $uninstallCmd) { continue }

            Write-Status "  Uninstalling $($entry.DisplayName)..." Yellow
            if ($uninstallCmd -match 'msiexec') {
                if ($uninstallCmd -notmatch '/quiet') {
                    $uninstallCmd = $uninstallCmd -replace '/I', '/X' -replace '/i', '/x'
                    if ($uninstallCmd -notmatch '/quiet') { $uninstallCmd += ' /quiet /norestart' }
                }
                Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $uninstallCmd" -Wait -WindowStyle Hidden | Out-Null
                $removed = $true
            }
            else {
                Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$uninstallCmd`" /quiet /norestart" -Wait -WindowStyle Hidden | Out-Null
                $removed = $true
            }
        }

        return $removed
    }
    catch {
        Write-Warning "Error uninstalling .NET $Version $Type : $_"
        return $false
    }
}

# Function to compare version numbers
function Compare-Version {
    param(
        [string]$CurrentVersion,
        [string]$TargetVersion
    )

    if ([string]::IsNullOrEmpty($CurrentVersion) -or [string]::IsNullOrEmpty($TargetVersion)) {
        Write-Verbose "Version comparison failed - empty version string"
        return $false
    }

    try {
        # Clean versions - remove any non-numeric characters except dots
        $cleanCurrent = $CurrentVersion -replace '[^\d\.]', ''
        $cleanTarget = $TargetVersion -replace '[^\d\.]', ''

        # Normalize version parts (ensure both have same number of parts)
        $currentParts = $cleanCurrent.Split('.')
        $targetParts = $cleanTarget.Split('.')
        $maxParts = [Math]::Max($currentParts.Length, $targetParts.Length)

        # Pad with zeros to match part count
        while ($currentParts.Length -lt $maxParts) {
            $currentParts += "0"
        }
        while ($targetParts.Length -lt $maxParts) {
            $targetParts += "0"
        }

        $normalizedCurrent = $currentParts -join '.'
        $normalizedTarget = $targetParts -join '.'

        $current = [version]$normalizedCurrent
        $target = [version]$normalizedTarget

        $result = ($current -ge $target)
        Write-Verbose "Comparing $normalizedCurrent >= $normalizedTarget = $result"

        return $result
    }
    catch {
        Write-Verbose "Version comparison exception: $_"
        return $false
    }
}

# Function to get file version from an executable
function Get-InstallerVersion {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )

    try {
        if (Test-Path $FilePath) {
            $versionInfo = (Get-Item $FilePath).VersionInfo
            if ($versionInfo.FileVersion) {
                $cleanVersion = $versionInfo.FileVersion -replace '[^\d\.].*$', ''
                return $cleanVersion
            }
        }
    }
    catch {
        Write-Warning "Could not read installer version: $_"
    }

    return $null
}

# Function to download a file with retry logic and exponential backoff
function Invoke-WebRequestWithRetry {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Uri,
        [Parameter(Mandatory=$true)]
        [string]$OutFile,
        [int]$MaxRetries = 3,
        [int]$InitialDelaySeconds = 2
    )

    $attempt = 0
    $delay = $InitialDelaySeconds

    while ($attempt -lt $MaxRetries) {
        try {
            $attempt++
            Write-Verbose "Download attempt $attempt of $MaxRetries for $Uri"
            
            # Add cache-busting to ensure fresh download
            $downloadUri = Add-CacheBuster -Url $Uri

            Invoke-WebRequest -Uri $downloadUri -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
            Write-Verbose "Download successful on attempt $attempt"
            return $true
        }
        catch {
            $errorMessage = $_.Exception.Message

            if ($attempt -ge $MaxRetries) {
                Write-Warning "Download failed after $MaxRetries attempts: $errorMessage"
                throw
            }

            Write-Warning "Download attempt $attempt failed: $errorMessage. Retrying in $delay seconds..."
            Start-Sleep -Seconds $delay
            $delay = $delay * 2  # Exponential backoff
        }
    }

    return $false
}

# Function to validate downloaded file
function Test-DownloadedFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        [int]$MinimumSizeBytes = 1048576  # 1 MB minimum
    )

    if (-not (Test-Path $FilePath)) {
        Write-Warning "Downloaded file does not exist: $FilePath"
        return $false
    }

    $fileInfo = Get-Item $FilePath

    # Check file size
    if ($fileInfo.Length -lt $MinimumSizeBytes) {
        Write-Warning "Downloaded file is too small ($(($fileInfo.Length / 1MB).ToString('N2')) MB). Minimum: $(($MinimumSizeBytes / 1MB).ToString('N2')) MB"
        return $false
    }

    # Check file extension
    if ($fileInfo.Extension -ne '.exe') {
        Write-Warning "Downloaded file is not an executable (.exe): $($fileInfo.Extension)"
        return $false
    }

    # Verify digital signature (Microsoft signed)
    try {
        $signature = Get-AuthenticodeSignature -FilePath $FilePath -ErrorAction Stop

        if ($signature.Status -eq 'Valid') {
            $signerSubject = $signature.SignerCertificate.Subject
            # Check if signed by Microsoft
            if ($signerSubject -match 'Microsoft' -or $signerSubject -match 'CN=Microsoft Corporation') {
                Write-Verbose "File signature is valid and signed by Microsoft"
                return $true
            }
            else {
                Write-Warning "File is signed but not by Microsoft: $signerSubject"
                return $false
            }
        }
        else {
            Write-Warning "File signature is invalid or missing: $($signature.Status)"
            return $false
        }
    }
    catch {
        Write-Warning "Could not verify file signature: $_"
        return $false
    }
}

# Function to get latest version and download URL from Microsoft releases-index.json
function Get-DotNetLatestVersion {
    param(
        [int]$MajorVersion
    )

    try {
        $releasesIndexUrl = "https://github.com/dotnet/core/raw/refs/heads/main/release-notes/releases-index.json"
        $releasesIndexUrl = Add-CacheBuster -Url $releasesIndexUrl
        Write-Verbose "Fetching releases-index.json from: $releasesIndexUrl"
        $response = Invoke-WebRequest -Uri $releasesIndexUrl -UseBasicParsing -ErrorAction Stop
        $releasesIndex = $response.Content | ConvertFrom-Json
        
        $channelVersion = "$MajorVersion.0"
        Write-Verbose "Looking for channel version: $channelVersion"
        $releasesArray = $releasesIndex.'releases-index'
        
        if (-not $releasesArray) {
            Write-Verbose "releases-index property not found in JSON response"
            return $null
        }
        
        $releaseInfo = $releasesArray | Where-Object { $_.'channel-version' -eq $channelVersion } | Select-Object -First 1
        
        if ($releaseInfo) {
            $latestRuntime = $releaseInfo.'latest-runtime'
            Write-Verbose "Found latest runtime version: $latestRuntime for channel $channelVersion"
            return $latestRuntime
        }
        else {
            Write-Verbose "No release info found for channel version $channelVersion"
        }
        
        return $null
    }
    catch {
        Write-Verbose "Could not get latest version from releases-index: $_"
        Write-Verbose "Error type: $($_.Exception.GetType().FullName)"
        Write-Verbose "Error message: $($_.Exception.Message)"
        return $null
    }
}

# Function to get download URL directly from releases.json
function Get-DotNetDownloadUrlFromReleases {
    param(
        [int]$MajorVersion,
        [string]$Component = "Desktop",
        [string]$Version
    )

    try {
        $releasesJsonUrl = "https://builds.dotnet.microsoft.com/dotnet/release-metadata/$MajorVersion.0/releases.json"
        $releasesJsonUrl = Add-CacheBuster -Url $releasesJsonUrl
        Write-Verbose "Fetching releases.json from: $releasesJsonUrl"
        $response = Invoke-WebRequest -Uri $releasesJsonUrl -UseBasicParsing -ErrorAction Stop
        $releases = $response.Content | ConvertFrom-Json
        
        # Find the release matching our version - try different property names
        $release = $null
        if ($releases.releases) {
            $release = $releases.releases | Where-Object { 
                ($_.'release-version' -eq $Version) -or 
                ($_.'releaseVersion' -eq $Version) -or
                ($_.version -eq $Version)
            } | Select-Object -First 1
        }
        elseif ($releases | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -match 'release' }) {
            # Try to find releases array with different casing
            $releasesProp = $releases | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -match 'release' } | Select-Object -First 1
            if ($releasesProp) {
                $releasesArray = $releases.($releasesProp.Name)
                $release = $releasesArray | Where-Object { 
                    ($_.'release-version' -eq $Version) -or 
                    ($_.'releaseVersion' -eq $Version) -or
                    ($_.version -eq $Version)
                } | Select-Object -First 1
            }
        }
        
        if (-not $release) {
            Write-Verbose "No release found matching version $Version in releases.json"
            Write-Verbose "Available releases: $(if ($releases.releases) { ($releases.releases | Select-Object -First 3 | ForEach-Object { $_.'release-version' -or $_.version }) -join ', ' } else { 'none found' })"
            return $null
        }

        # Microsoft nests installers under component objects (runtime, windowsdesktop, etc.)
        $files = $null
        $componentPropertyMap = @{
            Desktop    = 'windowsdesktop'
            AspNetCore = 'aspnetcore-runtime'
            Runtime    = 'runtime'
            SDK        = 'sdk'
        }

        if ($componentPropertyMap.ContainsKey($Component)) {
            $componentNode = $release.($componentPropertyMap[$Component])
            if ($componentNode -and $componentNode.files) {
                $files = $componentNode.files
            }
            elseif ($Component -eq 'SDK' -and $release.sdks) {
                $sdkWithFiles = @($release.sdks) | Where-Object { $_.files } | Select-Object -First 1
                if ($sdkWithFiles) {
                    $files = $sdkWithFiles.files
                }
            }
        }

        if (-not $files -and $release.files) {
            $files = $release.files
        }
        elseif (-not $files -and $release.Files) {
            $files = $release.Files
        }

        if (-not $files) {
            Write-Verbose "No files found in release $Version for component $Component"
            return $null
        }
        
        Write-Verbose "Found $($files.Count) files in release $Version"
        # Debug: Show first few file names
        $sampleFiles = $files | Select-Object -First 3 | ForEach-Object { $_.name -or $_.Name }
        Write-Verbose "Sample files: $($sampleFiles -join ', ')"
        
        if ($Component -eq "Desktop") {
            $file = $files | Where-Object {
                ($_.name -match 'windowsdesktop.*runtime' -or $_.Name -match 'windowsdesktop.*runtime') -and
                ($_.rid -eq 'win-x64' -or $_.Rid -eq 'win-x64') -and
                ($_.name -match '\.exe$' -or $_.Name -match '\.exe$')
            } | Select-Object -First 1
        }
        elseif ($Component -eq "AspNetCore") {
            $file = $files | Where-Object {
                ($_.name -match '^aspnetcore-runtime' -or $_.Name -match '^aspnetcore-runtime') -and
                ($_.name -notmatch 'composite' -and $_.Name -notmatch 'composite') -and
                ($_.rid -eq 'win-x64' -or $_.Rid -eq 'win-x64') -and
                ($_.name -match '\.exe$' -or $_.Name -match '\.exe$')
            } | Select-Object -First 1
        }
        elseif ($Component -eq "Runtime") {
            $file = $files | Where-Object {
                ($_.name -match '^dotnet-runtime' -or $_.Name -match '^dotnet-runtime') -and
                ($_.rid -eq 'win-x64' -or $_.Rid -eq 'win-x64') -and
                ($_.name -match '\.exe$' -or $_.Name -match '\.exe$')
            } | Select-Object -First 1
        }
        else {
            $file = $files | Where-Object {
                ($_.name -match '^dotnet-sdk' -or $_.Name -match '^dotnet-sdk') -and
                ($_.rid -eq 'win-x64' -or $_.Rid -eq 'win-x64') -and
                ($_.name -match '\.exe$' -or $_.Name -match '\.exe$')
            } | Select-Object -First 1
        }
        
        if ($file) {
            # Try all possible URL property names
            $downloadUrl = $null
            $possibleUrlProps = @('url', 'Url', 'downloadUrl', 'DownloadUrl', 'download-url', 'href', 'Href', 'link', 'Link')
            foreach ($prop in $possibleUrlProps) {
                if ($file.PSObject.Properties.Name -contains $prop) {
                    $downloadUrl = $file.$prop
                    Write-Verbose "Found download URL in property '$prop': $downloadUrl"
                    break
                }
            }
            
            if ($downloadUrl) {
                # Verify the URL is valid by testing HEAD request
                try {
                    Write-Verbose "Verifying download URL..."
                    $verifyUrl = Add-CacheBuster -Url $downloadUrl
                    $headResponse = Invoke-WebRequest -Uri $verifyUrl -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                    if ($headResponse.StatusCode -eq 200) {
                        Write-Verbose "Download URL verified successfully"
                        return $downloadUrl
                    }
                    else {
                        Write-Verbose "URL verification returned status code: $($headResponse.StatusCode)"
                    }
                }
                catch {
                    Write-Verbose "URL verification failed: $_"
                    # Still return the URL even if verification fails - it might work for actual download
                    return $downloadUrl
                }
            }
            else {
                $allProps = ($file | Get-Member -MemberType NoteProperty).Name -join ', '
                Write-Verbose "File found but no URL property found. Available properties: $allProps"
                Write-Verbose "File object: $($file | ConvertTo-Json -Depth 2)"
                Write-Verbose "File name: $($file.name -or $file.Name), RID: $($file.rid -or $file.Rid)"
            }
        }
        else {
            Write-Verbose "No matching file found for Component=$Component, RID=win-x64 in release $Version"
            $availableFiles = ($files | Select-Object -First 5 | ForEach-Object { 
                $name = $_.name -or $_.Name
                $rid = $_.rid -or $_.Rid
                "$name (RID: $rid)"
            }) -join ', '
            Write-Verbose "No matching installer for Component=$Component, RID=win-x64"
            Write-Verbose "Available files (first 5): $availableFiles"
        }
        
        return $null
    }
    catch {
        Write-Verbose "Could not get download URL from releases.json: $_"
        Write-Verbose "Error details: $($_.Exception.Message)"
        return $null
    }
}

# Function to get download URL for .NET major version
function Get-DotNetDownloadUrl {
    param(
        [int]$MajorVersion,
        [string]$Component = "Desktop"  # Runtime, Desktop, AspNetCore, or SDK
    )

    $maxRetries = 3
    $attempt = 0
    $delay = 2

    while ($attempt -lt $maxRetries) {
        try {
            $attempt++
            Write-Verbose "Fetching download URL attempt $attempt of $maxRetries"
            Write-Status "  Attempt ${attempt} of ${maxRetries}: Getting download URL for .NET ${MajorVersion}.0 ${Component}..."

            # First, try to get the latest version from the API
            Write-Verbose "Getting latest version for .NET $MajorVersion.0 from Microsoft API..."
            Write-Status "  Querying Microsoft API for latest version..."
            $latestVersion = Get-DotNetLatestVersion -MajorVersion $MajorVersion
            
            if ($latestVersion) {
                Write-Status "  Latest available version: $latestVersion" Green
                
                # First, try to get URL directly from releases.json (most reliable)
                Write-Verbose "Attempting to get download URL from releases.json API..."
                Write-Status "  Trying releases.json API method..."
                $directUrl = Get-DotNetDownloadUrlFromReleases -MajorVersion $MajorVersion -Component $Component -Version $latestVersion
                
                if ($directUrl) {
                    Write-Verbose "Successfully got download URL from releases.json: $directUrl"
                    Write-Status "  Download URL retrieved successfully" Green
                    return $directUrl
                }
                else {
                    Write-Verbose "releases.json API method returned no URL"
                    Write-Status "  releases.json API method failed, trying redirect..."
                }
                
                Write-Verbose "releases.json method failed, trying redirect following..."
                Write-Status "  Attempting redirect resolution..."
                
                $thankYouUrl = if ($Component -eq "Desktop") {
                    "https://dotnet.microsoft.com/en-us/download/dotnet/thank-you/runtime-desktop-$latestVersion-windows-x64-installer"
                } elseif ($Component -eq "AspNetCore") {
                    "https://dotnet.microsoft.com/en-us/download/dotnet/thank-you/runtime-aspnetcore-$latestVersion-windows-x64-installer"
                } elseif ($Component -eq "Runtime") {
                    "https://dotnet.microsoft.com/en-us/download/dotnet/thank-you/runtime-$latestVersion-windows-x64-installer"
                } else {
                    "https://dotnet.microsoft.com/en-us/download/dotnet/thank-you/sdk-$latestVersion-windows-x64-installer"
                }
                
                Write-Verbose "Thank-you URL: $thankYouUrl"
                
                # Add cache-busting to thank-you URL
                $thankYouUrl = Add-CacheBuster -Url $thankYouUrl
                
                # Try multiple methods to follow redirects
                $actualUrl = $null
                
                # Method 1: Use Invoke-WebRequest with MaximumRedirectionCount
                try {
                    Write-Verbose "Trying Invoke-WebRequest with redirects..."
                    $response = Invoke-WebRequest -Uri $thankYouUrl -UseBasicParsing -MaximumRedirectionCount 10 -ErrorAction Stop
                    # Try to get final URL from response
                    if ($response.BaseResponse) {
                        $actualUrl = $response.BaseResponse.RequestMessage.RequestUri.AbsoluteUri
                    }
                    elseif ($response.Headers.Location) {
                        $actualUrl = $response.Headers.Location
                    }
                    Write-Verbose "Invoke-WebRequest resolved URL: $actualUrl"
                }
                catch {
                    Write-Verbose "Invoke-WebRequest redirect failed: $_"
                }
                
                # Method 2: Use HttpWebRequest if Method 1 didn't work
                if (-not $actualUrl -or ($actualUrl -notmatch '\.exe$' -and $actualUrl -notmatch 'download\.visualstudio\.microsoft\.com')) {
                    try {
                        Write-Verbose "Trying HttpWebRequest redirect..."
                        $request = [System.Net.HttpWebRequest]::Create($thankYouUrl)
                        $request.Method = "HEAD"
                        $request.AllowAutoRedirect = $true
                        $request.Timeout = 20000
                        $request.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
                        $request.MaximumAutomaticRedirections = 10
                        $response = $request.GetResponse()
                        $actualUrl = $response.ResponseUri.AbsoluteUri
                        $response.Close()
                        Write-Verbose "HttpWebRequest resolved URL: $actualUrl"
                    }
                    catch {
                        Write-Verbose "HttpWebRequest redirect failed: $_"
                    }
                }
                
                # Method 3: Try to get Location header manually
                if (-not $actualUrl -or ($actualUrl -notmatch '\.exe$' -and $actualUrl -notmatch 'download\.visualstudio\.microsoft\.com')) {
                    try {
                        Write-Verbose "Trying manual Location header check..."
                        $request = [System.Net.HttpWebRequest]::Create($thankYouUrl)
                        $request.Method = "HEAD"
                        $request.AllowAutoRedirect = $false
                        $request.Timeout = 20000
                        $request.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
                        try {
                            $response = $request.GetResponse()
                            $response.Close()
                        }
                        catch {
                            # 302/301 redirect expected
                            if ($_.Exception.Response) {
                                $location = $_.Exception.Response.Headers['Location']
                                if ($location) {
                                    $actualUrl = $location
                                    Write-Verbose "Found Location header: $actualUrl"
                                    # If relative URL, make it absolute
                                    if ($actualUrl -notmatch '^https?://') {
                                        $baseUri = New-Object System.Uri($thankYouUrl)
                                        $actualUrl = New-Object System.Uri($baseUri, $actualUrl).AbsoluteUri
                                    }
                                }
                            }
                        }
                    }
                    catch {
                        Write-Verbose "Manual Location header check failed: $_"
                    }
                }
                
                if ($actualUrl) {
                    Write-Verbose "Resolved URL: $actualUrl"
                    
                    # Check if it's a valid download URL
                    if ($actualUrl -match '\.exe$' -or $actualUrl -match 'download\.visualstudio\.microsoft\.com') {
                        Write-Verbose "Successfully resolved download URL: $actualUrl"
                        Write-Status "  Download URL resolved successfully" Green
                        return $actualUrl
                    }
                    else {
                        Write-Verbose "Resolved URL doesn't match expected pattern: $actualUrl"
                        # If we got a URL but it's not the final download, try following it again
                        if ($actualUrl -match 'thank-you' -or $actualUrl -match 'dotnet\.microsoft\.com') {
                            Write-Verbose "Got intermediate redirect, trying to follow further..."
                            try {
                                $finalRequest = [System.Net.HttpWebRequest]::Create($actualUrl)
                                $finalRequest.Method = "HEAD"
                                $finalRequest.AllowAutoRedirect = $true
                                $finalRequest.Timeout = 20000
                                $finalRequest.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
                                $finalResponse = $finalRequest.GetResponse()
                                $finalUrl = $finalResponse.ResponseUri.AbsoluteUri
                                $finalResponse.Close()
                                
                                if ($finalUrl -match '\.exe$' -or $finalUrl -match 'download\.visualstudio\.microsoft\.com') {
                                    Write-Verbose "Successfully resolved final download URL: $finalUrl"
                                    Write-Status "  Download URL resolved successfully" Green
                                    return $finalUrl
                                }
                            }
                            catch {
                                Write-Verbose "Could not follow intermediate redirect: $_"
                            }
                        }
                        Write-Status "  Redirect resolution failed - URL doesn't match expected pattern" Yellow
                    }
                }
                else {
                    Write-Verbose "No URL resolved from redirect"
                    Write-Status "  Redirect resolution failed - no URL returned" Yellow
                }
            }
            else {
                Write-Verbose "Could not get latest version from API, falling back to HTML scraping"
                Write-Status "  API did not return a version (may be offline or version not found)" Yellow
                Write-Status "  Falling back to HTML scraping method..."
            }
            
            # Fallback: Try scraping the download page
            Write-Verbose "Falling back to HTML scraping method"
            Write-Status "  Attempting HTML scraping fallback..."
            $downloadPage = "https://dotnet.microsoft.com/en-us/download/dotnet/$MajorVersion.0"
            try {
                $downloadPage = Add-CacheBuster -Url $downloadPage
                $response = Invoke-WebRequest -Uri $downloadPage -UseBasicParsing -ErrorAction Stop
                $content = $response.Content
            }
            catch {
                Write-Verbose "Could not fetch download page: $_"
                if ($attempt -lt $maxRetries) {
                    Write-Warning "Could not fetch download page. Retrying in $delay seconds..."
                    Start-Sleep -Seconds $delay
                    $delay = $delay * 2
                    continue
                }
                else {
                    Write-Warning "Could not fetch download page after $maxRetries attempts"
                    return $null
                }
            }

            # Try multiple patterns to extract download URLs
            $patterns = @()
            if ($Component -eq "Desktop") {
                $patterns = @(
                    'href="(https://download\.visualstudio\.microsoft\.com/download/pr/[^"]+windowsdesktop-runtime-[^"]+win-x64\.exe)"'
                    'href="(https://[^"]+windowsdesktop-runtime-[^"]+win-x64\.exe)"'
                    'data-installer-url="([^"]+windowsdesktop-runtime-[^"]+win-x64\.exe)"'
                )
            } elseif ($Component -eq "AspNetCore") {
                $patterns = @(
                    'href="(https://download\.visualstudio\.microsoft\.com/download/pr/[^"]+aspnetcore-runtime-[^"]+win-x64\.exe)"'
                    'href="(https://[^"]+aspnetcore-runtime-[^"]+win-x64\.exe)"'
                    'data-installer-url="([^"]+aspnetcore-runtime-[^"]+win-x64\.exe)"'
                )
            } elseif ($Component -eq "Runtime") {
                $patterns = @(
                    'href="(https://download\.visualstudio\.microsoft\.com/download/pr/[^"]+dotnet-runtime-[^"]+win-x64\.exe)"'
                    'href="(https://[^"]+dotnet-runtime-[^"]+win-x64\.exe)"'
                    'data-installer-url="([^"]+dotnet-runtime-[^"]+win-x64\.exe)"'
                )
            } else {
                $patterns = @(
                    'href="(https://download\.visualstudio\.microsoft\.com/download/pr/[^"]+dotnet-sdk-[^"]+win-x64\.exe)"'
                    'href="(https://[^"]+dotnet-sdk-[^"]+win-x64\.exe)"'
                    'data-installer-url="([^"]+dotnet-sdk-[^"]+win-x64\.exe)"'
                )
            }

            foreach ($pattern in $patterns) {
                if ($content -match $pattern) {
                    $url = $matches[1]
                    # Clean up the URL (remove any trailing quotes or parameters)
                    if ($url -match '^(.+?)(["'']|[\?&]).*$') {
                        $url = $matches[1]
                    }
                    Write-Verbose "Successfully extracted download URL using pattern: $url"
                    return $url
                }
            }

            # Pattern didn't match - log and retry
            if ($attempt -lt $maxRetries) {
                Write-Warning "Could not extract download URL from page (attempt $attempt/$maxRetries). Retrying in $delay seconds..."
                Start-Sleep -Seconds $delay
                $delay = $delay * 2
            }
            else {
                Write-Warning "All URL extraction methods failed after $maxRetries attempts"
            }
        }
        catch {
            $errorMessage = $_.Exception.Message

            if ($attempt -ge $maxRetries) {
                Write-Warning "Could not get .NET $MajorVersion download URL after $maxRetries attempts: $errorMessage"
                return $null
            }

            Write-Warning "Attempt $attempt failed: $errorMessage. Retrying in $delay seconds..."
            Start-Sleep -Seconds $delay
            $delay = $delay * 2
        }
    }

    Write-Warning "Could not extract download URL from Microsoft page after $maxRetries attempts"
    return $null
}

$script:SilentArgsMap = @{
    "Framework" = "/quiet", "/norestart"
    "NET" = "/install", "/quiet", "/norestart"
}

function Install-DotNetProcess {
    param(
        [System.Diagnostics.Process]$Process,
        [ref]$RebootRequired
    )

    switch ($Process.ExitCode) {
        0 {
            Write-Status "  Installation successful." Green
            return $true
        }
        3010 {
            Write-Status "  Installation successful. Reboot required." Yellow
            $RebootRequired.Value = $true
            return $true
        }
        1641 {
            Write-Status "  Installation successful. Reboot initiated." Yellow
            $RebootRequired.Value = $true
            return $true
        }
        default {
            Write-Warning "  Exit code: $($Process.ExitCode) (may indicate already updated or minor issue)"
            return $false
        }
    }
}

function Update-DotNetComponent {
    param(
        [int]$MajorVersion,
        [string]$Component,
        [string]$CurrentVersion,
        [string]$TempDir,
        [ref]$RebootRequired,
        [ref]$DownloadedFiles
    )

    $componentLabels = @{
        Desktop    = "Desktop Runtime"
        AspNetCore = "ASP.NET Core Runtime"
        Runtime    = "Runtime"
        SDK        = "SDK"
    }
    $displayName = $componentLabels[$Component]

    if (-not (Test-DotNetVersionSupported -DotNetMajorVersion $MajorVersion)) {
        Write-Status "  .NET $MajorVersion $displayName is not supported on this OS - Skipping" Yellow
        return
    }

    Write-Status "  Checking .NET $MajorVersion $displayName (current: $CurrentVersion)..."

    $latestVersion = Get-DotNetLatestVersion -MajorVersion $MajorVersion
    if ($latestVersion -and (Compare-Version -CurrentVersion $CurrentVersion -TargetVersion $latestVersion)) {
        Write-Status "  .NET $MajorVersion $displayName is up to date ($CurrentVersion)" Cyan
        return
    }

    $url = Get-DotNetDownloadUrl -MajorVersion $MajorVersion -Component $Component
    if (-not $url) {
        Write-Warning "  Could not get download URL for .NET $MajorVersion $displayName."
        return
    }

    $tempInstallerPath = Join-Path $TempDir "dotnet-$MajorVersion.0-$($Component.ToLower())-check.exe"

    try {
        Write-Status "  Downloading .NET $MajorVersion $displayName..."
        Invoke-WebRequestWithRetry -Uri $url -OutFile $tempInstallerPath

        if (-not (Test-DownloadedFile -FilePath $tempInstallerPath -MinimumSizeBytes 1048576)) {
            Write-Warning "  Downloaded file validation failed for .NET $MajorVersion $displayName."
            Remove-Item -Path $tempInstallerPath -Force -ErrorAction SilentlyContinue
            return
        }

        $installerVersion = Get-InstallerVersion -FilePath $tempInstallerPath
        if ($installerVersion -and (Compare-Version -CurrentVersion $CurrentVersion -TargetVersion $installerVersion)) {
            Write-Status "  .NET $MajorVersion $displayName is up to date ($CurrentVersion)" Cyan
            Remove-Item -Path $tempInstallerPath -Force -ErrorAction SilentlyContinue
            return
        }

        $installerPath = Join-Path $TempDir "dotnet-$MajorVersion.0-$($Component.ToLower()).exe"
        Move-Item -Path $tempInstallerPath -Destination $installerPath -Force
        $DownloadedFiles.Value += $installerPath

        $targetLabel = if ($installerVersion) { $installerVersion } else { "latest" }
        Write-Status "  Update available: $CurrentVersion -> $targetLabel" Yellow
        Write-Status "  Installing .NET $MajorVersion $displayName..."

        $process = Start-Process -FilePath $installerPath -ArgumentList $script:SilentArgsMap["NET"] -Wait -PassThru -WindowStyle Hidden
        Install-DotNetProcess -Process $process -RebootRequired $RebootRequired | Out-Null
    }
    catch {
        Write-Warning "  Failed to update .NET $MajorVersion $displayName : $_"
        if (Test-Path $tempInstallerPath) {
            Remove-Item -Path $tempInstallerPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# Scan for installed versions
Write-Host "Scanning for installed .NET versions..." -ForegroundColor Yellow
Write-Host ""

$installedVersions = @{}
$updateCount = 0

# Check .NET Framework versions - detect installed version and check for updates
$releaseValue = Get-DotNetFrameworkVersion -RegistryPath "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -RegistryValue "Release"

if ($releaseValue) {
    Write-Host "Found .NET Framework release value: $releaseValue" -ForegroundColor Gray

    # Determine the currently installed Framework version
    $frameworkVersions = $DotNetVersions.Keys | Where-Object { $DotNetVersions[$_].IsFramework } | Sort-Object { $DotNetVersions[$_].MinRelease } -Descending

    $currentFrameworkVersion = $null
    foreach ($version in $frameworkVersions) {
        $dotNetInfo = $DotNetVersions[$version]

        if ($releaseValue -ge $dotNetInfo.MinRelease) {
            Write-Host "Detected .NET Framework $($dotNetInfo.TargetVersion) installed (Release: $releaseValue)" -ForegroundColor Gray
            $currentFrameworkVersion = $version
            break
        }
    }

    # Check if there's a newer Framework version available
    if ($currentFrameworkVersion) {
        # Find the highest Framework version available
        $newerVersions = $DotNetVersions.Keys | Where-Object {
            $DotNetVersions[$_].IsFramework -and $DotNetVersions[$_].MinRelease -gt $releaseValue
        } | Sort-Object { $DotNetVersions[$_].MinRelease } -Descending

        if ($newerVersions) {
            $targetVersion = $newerVersions | Select-Object -First 1
            $targetInfo = $DotNetVersions[$targetVersion]
            $rebootPending = Test-SystemRebootPending

            if ($rebootPending) {
                Write-Host ".NET Framework $($targetInfo.TargetVersion) is staged but reboot is required to complete (Release still: $releaseValue)" -ForegroundColor Yellow
                $installedVersions[$targetVersion] = @{
                    Installed = $false
                    CurrentReleaseValue = $releaseValue
                    TargetReleaseValue = $targetInfo.MinRelease
                    CurrentVersion = $DotNetVersions[$currentFrameworkVersion].TargetVersion
                    TargetVersion = $targetInfo.TargetVersion
                    IsFramework = $true
                    NeedsUpdate = $false
                    PendingReboot = $true
                }
            }
            else {
                Write-Host "Newer .NET Framework version available: $($targetInfo.TargetVersion) (Release: $($targetInfo.MinRelease))" -ForegroundColor Yellow
                $installedVersions[$targetVersion] = @{
                    Installed = $false
                    CurrentReleaseValue = $releaseValue
                    TargetReleaseValue = $targetInfo.MinRelease
                    CurrentVersion = $DotNetVersions[$currentFrameworkVersion].TargetVersion
                    TargetVersion = $targetInfo.TargetVersion
                    IsFramework = $true
                    NeedsUpdate = $true
                    PendingReboot = $false
                }
                $updateCount++
            }
        } else {
            Write-Host ".NET Framework is up to date ($($DotNetVersions[$currentFrameworkVersion].TargetVersion))" -ForegroundColor Green
        }
    }
}

# Check .NET (Core/5+) versions
Write-Host "Checking .NET (Core/5+) versions..." -ForegroundColor Gray
$dotnetInfo = Get-InstalledDotNetVersions
if (-not $dotnetInfo) {
    $dotnetInfo = @{ Available = $false; Runtimes = @(); SDKs = @() }
}

if ($dotnetInfo.Available) {
    Write-Verbose "Checking for installed .NET versions. Found $($dotnetInfo.Runtimes.Count) runtimes and $($dotnetInfo.SDKs.Count) SDKs"
    
    # Debug: Show what we found
    if ($dotnetInfo.Runtimes.Count -eq 0 -and $dotnetInfo.SDKs.Count -eq 0) {
        Write-Verbose "dotnet command returned no runtimes or SDKs"
    }
    else {
        Write-Verbose "Sample runtime output: $($dotnetInfo.Runtimes[0..([Math]::Min(2, $dotnetInfo.Runtimes.Count-1))] -join ' | ')"
        Write-Verbose "Sample SDK output: $($dotnetInfo.SDKs[0..([Math]::Min(2, $dotnetInfo.SDKs.Count-1))] -join ' | ')"
    }
    
    foreach ($version in $DotNetVersions.Keys | Where-Object { -not $DotNetVersions[$_].IsFramework } | Sort-Object) {
        $netInfo = $DotNetVersions[$version]
        $majorVersion = $version.Split('-')[1].Split('.')[0]
        
        Write-Verbose "Checking for .NET $majorVersion.x installations..."
        
        # Check for runtime installations - escape the major version for regex
        $runtimePattern = "Microsoft\.NETCore\.App $([regex]::Escape($majorVersion))\."
        $desktopPattern = "Microsoft\.WindowsDesktop\.App $([regex]::Escape($majorVersion))\."
        $aspCorePattern = "Microsoft\.AspNetCore\.App $([regex]::Escape($majorVersion))\."
        $sdkPattern = "^$([regex]::Escape($majorVersion))\."
        
        $runtimeMatch = $dotnetInfo.Runtimes | Where-Object { $_ -match $runtimePattern }
        $desktopMatch = $dotnetInfo.Runtimes | Where-Object { $_ -match $desktopPattern }
        $aspCoreMatch = $dotnetInfo.Runtimes | Where-Object { $_ -match $aspCorePattern }
        $sdkMatch = $dotnetInfo.SDKs | Where-Object { $_ -match $sdkPattern }
        
        Write-Verbose "  Runtime matches: $($runtimeMatch.Count)"
        Write-Verbose "  Desktop matches: $($desktopMatch.Count)"
        Write-Verbose "  ASP.NET Core matches: $($aspCoreMatch.Count)"
        Write-Verbose "  SDK matches: $($sdkMatch.Count)"
        
        if ($runtimeMatch -or $desktopMatch -or $aspCoreMatch -or $sdkMatch) {
            $installedVersions[$version] = @{
                Installed = $true
                Runtime = $runtimeMatch
                Desktop = $desktopMatch
                AspCore = $aspCoreMatch
                SDK = $sdkMatch
                IsFramework = $false
            }
            $updateCount++
            Write-Verbose "  Found .NET $majorVersion.x installation"
        }
    }
}
else {
    Write-Verbose "dotnet command not available or failed"
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "Detection Results" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

if ($installedVersions.Count -eq 0) {
    Write-Host "No .NET installations detected." -ForegroundColor Yellow
    if (-not $DryRun) {
        Write-Host "Nothing to update." -ForegroundColor Yellow
        exit 0
    }
}

# Display what was found
foreach ($version in $installedVersions.Keys | Sort-Object) {
    $netInfo = $DotNetVersions[$version]
    $installed = $installedVersions[$version]

    Write-Host ""
    if ($installed.IsFramework) {
        if ($installed.PendingReboot) {
            Write-Host ".NET Framework $($installed.TargetVersion):" -ForegroundColor Yellow
            Write-Host "  Current: $($installed.CurrentVersion) (Release: $($installed.CurrentReleaseValue))" -ForegroundColor Gray
            Write-Host "  Status: PENDING REBOOT" -ForegroundColor Yellow
        }
        elseif ($installed.NeedsUpdate) {
            Write-Host ".NET Framework Update Available:" -ForegroundColor Yellow
            Write-Host "  Current: $($installed.CurrentVersion) (Release: $($installed.CurrentReleaseValue))" -ForegroundColor Gray
            Write-Host "  Target: $($installed.TargetVersion) (Release: $($installed.TargetReleaseValue))" -ForegroundColor Gray
            Write-Host "  Status: UPDATE REQUIRED" -ForegroundColor Yellow
        } else {
            Write-Host ".NET Framework $($netInfo.TargetVersion):" -ForegroundColor Green
            Write-Host "  Release Value: $($installed.ReleaseValue)" -ForegroundColor Gray
            Write-Host "  Status: INSTALLED" -ForegroundColor Green
        }
    }
    else {
        Write-Host ".NET $($version.Split('-')[1]):" -ForegroundColor Green
        if ($installed.Runtime) {
            Write-Host "  Runtime: $($installed.Runtime)" -ForegroundColor Gray
        }
        if ($installed.Desktop) {
            Write-Host "  Desktop: $($installed.Desktop)" -ForegroundColor Gray
        }
        if ($installed.AspCore) {
            Write-Host "  ASP.NET Core: $($installed.AspCore)" -ForegroundColor Gray
        }
        if ($installed.SDK) {
            Write-Host "  SDK: $($installed.SDK)" -ForegroundColor Gray
        }
    }
}

Write-Host ""
Write-Host "Total .NET installations found: $($installedVersions.Count)" -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Invoke-DryRunReport -InstalledVersions $installedVersions -DotNetVersionsTable $DotNetVersions -DotNetInfo $dotnetInfo
    exit 0
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Administrator privileges are required to install updates. Use -DryRun to scan without installing."
    exit 1
}

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "Beginning updates..." -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Temporary directory for downloads
$TempDir = $env:TEMP
$RebootRequired = $false
$downloadedFiles = @()

try {
    $currentUpdate = 0
    
    foreach ($version in $installedVersions.Keys | Sort-Object) {
        $netInfo = $DotNetVersions[$version]
        $installed = $installedVersions[$version]
        
        Write-Host "Processing .NET $version..." -ForegroundColor Yellow
        Write-Host ""
        
        $currentUpdate++
        
        if ($installed.IsFramework) {
            if ($installed.PendingReboot) {
                Write-Host "[$currentUpdate/$($installedVersions.Count)] .NET Framework $($netInfo.TargetVersion) pending reboot - Skipping" -ForegroundColor Yellow
                Write-Host "  Restart the computer to complete the Framework update." -ForegroundColor Gray
                continue
            }

            if (-not $installed.NeedsUpdate) {
                continue
            }

            Write-Host "[$currentUpdate/$($installedVersions.Count)] Updating .NET Framework $($installed.CurrentVersion) to $($netInfo.TargetVersion)..." -ForegroundColor Cyan

            # Check OS compatibility for .NET Framework 4.8.1
            if ($netInfo.TargetVersion -eq "4.8.1" -and -not $script:SupportsDotNet481) {
                Write-Host "  .NET Framework 4.8.1 is not supported on this OS version - Skipping" -ForegroundColor Yellow
                Write-Host "  Requires Windows 10 1607+ or Windows Server 2016+" -ForegroundColor Gray
                continue
            }

            # For Framework, we'll use the offline installer
            $url = $netInfo.URLs.Offline
            $installerPath = Join-Path $TempDir "dotnet-framework-$($netInfo.TargetVersion).exe"
            $downloadedFiles += $installerPath

            try {
                Write-Host "  Downloading .NET Framework $($netInfo.TargetVersion)..."
                Invoke-WebRequestWithRetry -Uri $url -OutFile $installerPath
                Write-Host "  Download complete." -ForegroundColor Green

                # Validate downloaded file
                Write-Host "  Validating downloaded file..." -ForegroundColor Gray
                if (-not (Test-DownloadedFile -FilePath $installerPath -MinimumSizeBytes 1048576)) {
                    Write-Warning "  Downloaded file validation failed. Skipping installation."
                    continue
                }
                Write-Host "  Validation successful." -ForegroundColor Green

                if (Test-Path $installerPath) {
                    Write-Host "  Installing .NET Framework $($netInfo.TargetVersion)..."
                    $process = Start-Process -FilePath $installerPath -ArgumentList $script:SilentArgsMap["Framework"] -Wait -PassThru -WindowStyle Hidden
                    Install-DotNetProcess -Process $process -RebootRequired ([ref]$RebootRequired) | Out-Null
                }
            }
            catch {
                Write-Warning "  Failed: $_"
            }
        }
        else {
            $majorVersion = [int]$version.Split('-')[1].Split('.')[0]
            Write-Host "[$currentUpdate/$($installedVersions.Count)] Checking .NET $($version.Split('-')[1])..." -ForegroundColor Cyan

            $componentsToUpdate = Get-InstalledDotNetComponents -Installed $installed

            if ($componentsToUpdate.Count -eq 0) {
                Write-Status "  No component versions detected - Skipping" Cyan
            }
            else {
                foreach ($component in $componentsToUpdate) {
                    Update-DotNetComponent -MajorVersion $majorVersion `
                        -Component $component.Type `
                        -CurrentVersion $component.CurrentVersion `
                        -TempDir $TempDir `
                        -RebootRequired ([ref]$RebootRequired) `
                        -DownloadedFiles ([ref]$downloadedFiles)
                }
            }
        }
        Write-Host ""
    }
    
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Update process completed." -ForegroundColor Green
    
    if ($RemoveOldVersions) {
        Write-Host ""
        Write-Host "=============================================" -ForegroundColor Cyan
        Write-Host "Checking for unused .NET versions to remove..." -ForegroundColor Cyan
        Write-Host "=============================================" -ForegroundColor Cyan
        Write-Host ""

        $dotnetInfo = Get-InstalledDotNetVersions
        $versionsToRemove = @()
        $majorsInUse = @{}

        if ($dotnetInfo.Available) {
            foreach ($runtime in $dotnetInfo.Runtimes) {
                if ($runtime -match 'Microsoft\.(NETCore|WindowsDesktop|AspNetCore)\.App (\d+)\.') {
                    $majorVersion = [int]$matches[2]
                    if ($majorVersion -ge 6) {
                        $majorsInUse[$majorVersion] = $true
                    }
                }
            }
            foreach ($sdk in $dotnetInfo.SDKs) {
                if ($sdk -match '^(\d+)\.') {
                    $majorsInUse[[int]$matches[1]] = $true
                }
            }

            $installedMajors = $majorsInUse.Keys | Sort-Object
            $newestMajor = ($installedMajors | Measure-Object -Maximum).Maximum

            foreach ($runtime in $dotnetInfo.Runtimes) {
                $candidates = @(
                    @{ Pattern = 'Microsoft\.NETCore\.App (\d+\.\d+\.\d+)'; Type = 'Runtime' }
                    @{ Pattern = 'Microsoft\.WindowsDesktop\.App (\d+\.\d+\.\d+)'; Type = 'Desktop' }
                    @{ Pattern = 'Microsoft\.AspNetCore\.App (\d+\.\d+\.\d+)'; Type = 'AspCore' }
                )
                foreach ($candidate in $candidates) {
                    if ($runtime -match $candidate.Pattern) {
                        $version = $matches[1]
                        $majorVersion = [int]$version.Split('.')[0]
                        if ($majorVersion -lt $newestMajor -and -not (Test-DotNetVersionInUse -MajorVersion $majorVersion)) {
                            $versionsToRemove += @{
                                Version = $version
                                Type = $candidate.Type
                                FullName = $runtime
                                MajorVersion = $majorVersion
                            }
                        }
                    }
                }
            }

            foreach ($sdk in $dotnetInfo.SDKs) {
                if ($sdk -match '^(\d+\.\d+\.\d+)') {
                    $version = $matches[1]
                    $majorVersion = [int]$version.Split('.')[0]
                    if ($majorVersion -lt $newestMajor -and -not (Test-DotNetVersionInUse -MajorVersion $majorVersion)) {
                        $versionsToRemove += @{
                            Version = $version
                            Type = 'SDK'
                            FullName = $sdk
                            MajorVersion = $majorVersion
                        }
                    }
                }
            }
        }

        $seen = @{}
        $versionsToRemove = $versionsToRemove | Where-Object {
            $key = "$($_.Type)-$($_.Version)"
            if ($seen[$key]) { $false } else { $seen[$key] = $true; $true }
        }

        if ($versionsToRemove.Count -gt 0) {
            Write-Host "Found $($versionsToRemove.Count) unused older version(s) to remove:" -ForegroundColor Yellow
            foreach ($item in $versionsToRemove) {
                Write-Host "  - $($item.FullName)" -ForegroundColor Gray
            }
            Write-Host ""

            $removedCount = 0
            foreach ($item in $versionsToRemove) {
                Write-Host "Removing $($item.Type) $($item.Version)..." -ForegroundColor Yellow
                if (Uninstall-DotNetVersion -Version $item.Version -Type $item.Type) {
                    $removedCount++
                }
                Write-Host ""
            }

            Write-Host "Removed $removedCount of $($versionsToRemove.Count) unused version(s)." -ForegroundColor $(if ($removedCount -eq $versionsToRemove.Count) { "Green" } else { "Yellow" })
        }
        else {
            Write-Host "No unused older .NET versions found to remove." -ForegroundColor Green
            Write-Host "Versions still referenced by apps, or only one major version is installed." -ForegroundColor Gray
        }

        Write-Host ""
        Write-Host "=============================================" -ForegroundColor Cyan
    }
    
    if ($RebootRequired) {
        Write-Host ""
        Write-Host "IMPORTANT: A system reboot is required." -ForegroundColor Yellow
        Write-Host "Please restart your computer to complete the updates." -ForegroundColor Yellow
    }
    Write-Host "=============================================" -ForegroundColor Cyan
}
catch {
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Red
    Write-Error "An error occurred: $_"
    Write-Host "=============================================" -ForegroundColor Red
    exit 1
}
finally {
    Write-Host ""
    Write-Host "Cleaning up temporary files..."
    
    foreach ($file in $downloadedFiles) {
        if (Test-Path $file) {
            try {
                Remove-Item -Path $file -Force -ErrorAction Stop
                Write-Host "  Removed: $(Split-Path $file -Leaf)" -ForegroundColor Gray
            }
            catch {
                Write-Warning "  Could not remove: $(Split-Path $file -Leaf)"
            }
        }
    }
    
    Write-Host "Cleanup complete."
}

exit 0

<#
.SYNOPSIS
    Comprehensive updater for all .NET Framework and .NET versions.

.DESCRIPTION
    This comprehensive script scans for and updates ALL major .NET versions:
    - .NET Framework 4.6.2, 4.7, 4.7.1, 4.7.2, 4.8, 4.8.1
    - .NET 6.0 LTS (keeps current version)
    - .NET 7.0, .NET 8.0 LTS (updates to latest .NET 9.0)
    - .NET 9.0 (if installed, keeps current version)
    
    The script runs completely silently with no user interaction required.
    It intelligently compares installed versions with target versions and skips updates
    for versions that are already up to date, saving time and bandwidth.

.NOTES
    File Name: dotnet-updater.ps1
    Run this script with administrative privileges.
    All URLs point to official Microsoft downloads.
    
    Version Checking:
    - .NET Framework: Compares against latest known versions
    - .NET (Core/5+): Downloads and checks latest available versions
    - Automatically detects if downloaded installer is newer than installed version
    - Skips installation if current version is already up to date
    - Avoids unnecessary downloads when versions are already current
    
    Target Versions:
    - .NET Framework 4.6.2: 4.6.2 (if installed)
    - .NET Framework 4.7: 4.7 (if installed) 
    - .NET Framework 4.7.1: 4.7.1 (if installed)
    - .NET Framework 4.7.2: 4.7.2 (if installed)
    - .NET Framework 4.8: 4.8 (if installed)
    - .NET Framework 4.8.1: 4.8.1 (latest)
    - .NET 6.0: Keep current LTS version (no update)
    - .NET 7.0: Update to latest .NET 9.0
    - .NET 8.0: Update to latest .NET 9.0
    - .NET 9.0: Keep current version (no update)
#>

#Requires -RunAsAdministrator

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
        Write-Host "  DEBUG: Error reading registry: $_" -ForegroundColor DarkGray
    }
    
    return $null
}

# Function to check installed .NET versions using dotnet command
function Get-InstalledDotNetVersions {
    try {
        $runtimes = & dotnet --list-runtimes 2>$null
        $sdks = & dotnet --list-sdks 2>$null
        
        return @{
            Runtimes = $runtimes
            SDKs = $sdks
            Available = $true
        }
    }
    catch {
        return @{
            Runtimes = @()
            SDKs = @()
            Available = $false
        }
    }
}

# Function to compare version numbers
function Compare-Version {
    param(
        [string]$CurrentVersion,
        [string]$TargetVersion
    )
    
    if ([string]::IsNullOrEmpty($CurrentVersion) -or [string]::IsNullOrEmpty($TargetVersion)) {
        Write-Host "  DEBUG: Version comparison failed - empty version string" -ForegroundColor DarkGray
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
        Write-Host "  DEBUG: Comparing $normalizedCurrent >= $normalizedTarget = $result" -ForegroundColor DarkGray
        
        return $result
    }
    catch {
        Write-Host "  DEBUG: Version comparison exception: $_" -ForegroundColor DarkGray
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

# Function to get the latest .NET 9.0 download URLs
function Get-DotNet9DownloadUrls {
    try {
        # Get download URL from Microsoft download page
        $downloadPage = "https://dotnet.microsoft.com/en-us/download/dotnet/9.0"
        $response = Invoke-WebRequest -Uri $downloadPage -UseBasicParsing
        $content = $response.Content
        
        # Extract the direct download URL for Desktop Runtime (x64)
        # The URL pattern is: href="https://download.visualstudio.microsoft.com/download/pr/.../windowsdesktop-runtime-9.x.x-win-x64.exe"
        if ($content -match 'https://download\.visualstudio\.microsoft\.com/download/pr/[^/]+/windowsdesktop-runtime-9\.\d+\.\d+-win-x64\.exe') {
            $desktopUrl = $matches[0] -replace 'href="', '' -replace '"', ''
            return @{
                Runtime = $desktopUrl
                Desktop = $desktopUrl
                SDK = $desktopUrl
            }
        }
        
        Write-Warning "Could not extract download URL from Microsoft page"
        return $null
    }
    catch {
        Write-Warning "Could not get .NET 9.0 download URLs: $_"
        return $null
    }
}

# Function to get download URL for .NET major version
function Get-DotNetDownloadUrl {
    param(
        [int]$MajorVersion,
        [string]$Component = "Desktop"  # Runtime, Desktop, or SDK
    )
    
    try {
        # Get download page
        $downloadPage = "https://dotnet.microsoft.com/en-us/download/dotnet/$MajorVersion.0"
        $response = Invoke-WebRequest -Uri $downloadPage -UseBasicParsing
        $content = $response.Content
        
        # Extract the direct download URL
        $pattern = if ($Component -eq "Desktop") {
            'href="(https://download\.visualstudio\.microsoft\.com/download/pr/[^/]+/windowsdesktop-runtime-\d+\.\d+\.\d+-win-x64\.exe)"'
        } elseif ($Component -eq "Runtime") {
            'href="(https://download\.visualstudio\.microsoft\.com/download/pr/[^/]+/dotnet-runtime-\d+\.\d+\.\d+-win-x64\.exe)"'
        } else {
            'href="(https://download\.visualstudio\.microsoft\.com/download/pr/[^/]+/dotnet-sdk-\d+\.\d+\.\d+-win-x64\.exe)"'
        }
        
        if ($content -match $pattern) {
            return $matches[1]
        }
        
        Write-Warning "Could not extract download URL from Microsoft page"
        return $null
    }
    catch {
        Write-Warning "Could not get .NET $MajorVersion download URL: $_"
        return $null
    }
}

# Scan for installed versions
Write-Host "Scanning for installed .NET versions..." -ForegroundColor Yellow
Write-Host ""

$installedVersions = @{}
$updateCount = 0

# Check .NET Framework versions - only detect the highest installed version
$releaseValue = Get-DotNetFrameworkVersion -RegistryPath "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -RegistryValue "Release"

if ($releaseValue) {
    Write-Host "Found .NET Framework release value: $releaseValue" -ForegroundColor Gray
    
    # Determine the highest Framework version based on release value
    $frameworkVersions = $DotNetVersions.Keys | Where-Object { $DotNetVersions[$_].IsFramework } | Sort-Object { $DotNetVersions[$_].MinRelease } -Descending
    
    foreach ($version in $frameworkVersions) {
        $dotNetInfo = $DotNetVersions[$version]
        
        if ($releaseValue -ge $dotNetInfo.MinRelease) {
            Write-Host "Detected .NET Framework $($dotNetInfo.TargetVersion) (Release: $releaseValue)" -ForegroundColor Gray
            
            $installedVersions[$version] = @{
                Installed = $true
                ReleaseValue = $releaseValue
                Version = $dotNetInfo.TargetVersion
                IsFramework = $true
            }
            $updateCount++
            break  # Only add the highest version detected
        }
    }
}

# Check .NET (Core/5+) versions
Write-Host "Checking .NET (Core/5+) versions..." -ForegroundColor Gray
$dotnetInfo = Get-InstalledDotNetVersions

if ($dotnetInfo.Available) {
    foreach ($version in $DotNetVersions.Keys | Where-Object { -not $DotNetVersions[$_].IsFramework } | Sort-Object) {
        $netInfo = $DotNetVersions[$version]
        $majorVersion = $version.Split('-')[1].Split('.')[0]
        
        # Check for runtime installations
        $runtimeMatch = $dotnetInfo.Runtimes | Where-Object { $_ -match "Microsoft\.NETCore\.App $majorVersion\." }
        $desktopMatch = $dotnetInfo.Runtimes | Where-Object { $_ -match "Microsoft\.WindowsDesktop\.App $majorVersion\." }
        $sdkMatch = $dotnetInfo.SDKs | Where-Object { $_ -match "^$majorVersion\." }
        
        if ($runtimeMatch -or $desktopMatch -or $sdkMatch) {
            $installedVersions[$version] = @{
                Installed = $true
                Runtime = $runtimeMatch
                Desktop = $desktopMatch
                SDK = $sdkMatch
                IsFramework = $false
            }
            $updateCount++
        }
    }
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "Detection Results" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

if ($installedVersions.Count -eq 0) {
    Write-Host "No .NET installations detected." -ForegroundColor Yellow
    Write-Host "Nothing to update." -ForegroundColor Yellow
    exit 0
}

# Display what was found
foreach ($version in $installedVersions.Keys | Sort-Object) {
    $netInfo = $DotNetVersions[$version]
    $installed = $installedVersions[$version]
    
    Write-Host ""
    if ($installed.IsFramework) {
        Write-Host ".NET Framework $($netInfo.TargetVersion):" -ForegroundColor Green
        Write-Host "  Release Value: $($installed.ReleaseValue)" -ForegroundColor Gray
        Write-Host "  Status: INSTALLED" -ForegroundColor Green
    }
    else {
        Write-Host ".NET $($version.Split('-')[1]):" -ForegroundColor Green
        if ($installed.Runtime) {
            Write-Host "  Runtime: $($installed.Runtime)" -ForegroundColor Gray
        }
        if ($installed.Desktop) {
            Write-Host "  Desktop: $($installed.Desktop)" -ForegroundColor Gray
        }
        if ($installed.SDK) {
            Write-Host "  SDK: $($installed.SDK)" -ForegroundColor Gray
        }
    }
}

Write-Host ""
Write-Host "Total .NET installations found: $($installedVersions.Count)" -ForegroundColor Cyan
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "Beginning updates..." -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Temporary directory for downloads
$TempDir = $env:TEMP
$RebootRequired = $false
$downloadedFiles = @()

# Silent installation arguments
$SilentArgsMap = @{
    "Framework" = "/quiet", "/norestart"
    "NET" = "/install", "/quiet", "/norestart"
}

try {
    $currentUpdate = 0
    
    foreach ($version in $installedVersions.Keys | Sort-Object) {
        $netInfo = $DotNetVersions[$version]
        $installed = $installedVersions[$version]
        
        Write-Host "Processing .NET $version..." -ForegroundColor Yellow
        Write-Host ""
        
        $currentUpdate++
        
        if ($installed.IsFramework) {
            # .NET Framework update logic
            Write-Host "[$currentUpdate/$($installedVersions.Count)] Checking .NET Framework $($netInfo.TargetVersion)..." -ForegroundColor Cyan
            
            # Check if current release value matches or exceeds the target
            if ($installed.ReleaseValue -ge $netInfo.MinRelease) {
                Write-Host "  .NET Framework $($netInfo.TargetVersion) is already installed (Release: $($installed.ReleaseValue)) - Skipping" -ForegroundColor Cyan
            }
            else {
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
                    Invoke-WebRequest -Uri $url -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
                    Write-Host "  Download complete." -ForegroundColor Green
                    
                    if (Test-Path $installerPath) {
                        Write-Host "  Installing .NET Framework $($netInfo.TargetVersion)..."
                        $silentArgs = $SilentArgsMap["Framework"]
                        $Process = Start-Process -FilePath $installerPath -ArgumentList $silentArgs -Wait -PassThru -WindowStyle Hidden
                        
                        switch ($Process.ExitCode) {
                            0 { 
                                Write-Host "  Installation successful." -ForegroundColor Green
                            }
                            3010 { 
                                Write-Host "  Installation successful. Reboot required." -ForegroundColor Yellow
                                $RebootRequired = $true
                            }
                            1641 {
                                Write-Host "  Installation successful. Reboot initiated." -ForegroundColor Yellow
                                $RebootRequired = $true
                            }
                            default { 
                                Write-Warning "  Exit code: $($Process.ExitCode) (may indicate already updated or minor issue)"
                            }
                        }
                    }
                }
                catch {
                    Write-Warning "  Failed: $_"
                }
            }
        }
        else {
            # .NET (Core/5+) update logic
            Write-Host "[$currentUpdate/$($installedVersions.Count)] Checking .NET $($version.Split('-')[1])..." -ForegroundColor Cyan
            
            # Extract current version from installed info
            $currentDesktopVersion = $null
            if ($installed.Desktop) {
                $versionMatch = $installed.Desktop -match "(\d+\.\d+\.\d+)"
                if ($versionMatch) {
                    $currentDesktopVersion = $matches[1]
                }
            }
            
            if ($currentDesktopVersion) {
                Write-Host "  Current .NET $($version.Split('-')[1]) Desktop Runtime: $currentDesktopVersion" -ForegroundColor Gray
                
                # Check if this is .NET 7.x or 8.x that should be updated to .NET 9.x
                $majorVersion = [int]$version.Split('-')[1].Split('.')[0]
                $shouldUpdateTo9 = ($majorVersion -eq 7 -or $majorVersion -eq 8)
                
                # Check OS compatibility before updating
                if (-not (Test-DotNetVersionSupported -DotNetMajorVersion "9")) {
                    Write-Host "  .NET 9 is not supported on this OS version - Skipping update" -ForegroundColor Yellow
                    Write-Host "  Current .NET $majorVersion will remain installed" -ForegroundColor Cyan
                    continue
                }
                
                if ($shouldUpdateTo9) {
                    # Check if .NET 9 is already installed
                    $dotnet9Installed = $installedVersions.Keys | Where-Object { $_ -match "NET-9\.0" }
                    
                    if ($dotnet9Installed) {
                        Write-Host "  .NET 9.0 is already installed - Skipping upgrade from .NET $majorVersion" -ForegroundColor Cyan
                        continue
                    }
                    
                    Write-Host "  .NET $($version.Split('-')[1]) detected - updating to latest .NET 9.x..." -ForegroundColor Yellow
                    
                    # Get the download URL dynamically from Microsoft
                    Write-Host "  Getting download URL from Microsoft..." -ForegroundColor Gray
                    $url = Get-DotNetDownloadUrl -MajorVersion 9 -Component "Desktop"
                    
                    if (-not $url) {
                        Write-Warning "  Could not get download URL. Skipping update."
                        continue
                    }
                    
                    Write-Host "  Download URL: $url" -ForegroundColor Gray
                    $installerPath = Join-Path $TempDir "dotnet-9.0-desktop.exe"
                    $downloadedFiles += $installerPath
                        
                        try {
                            Write-Host "  Downloading latest .NET 9.0 Desktop Runtime..."
                            Invoke-WebRequest -Uri $url -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
                            Write-Host "  Download complete." -ForegroundColor Green
                            
                            if (Test-Path $installerPath) {
                                # Check installer version
                                $installerVersion = Get-InstallerVersion -FilePath $installerPath
                                if ($installerVersion) {
                                    Write-Host "  Downloaded installer version: $installerVersion" -ForegroundColor Gray
                                }
                                
                                Write-Host "  Installing .NET 9.0 Desktop Runtime..."
                                $silentArgs = $SilentArgsMap["NET"]
                                $Process = Start-Process -FilePath $installerPath -ArgumentList $silentArgs -Wait -PassThru -WindowStyle Hidden
                                
                                switch ($Process.ExitCode) {
                                    0 { 
                                        Write-Host "  Installation successful." -ForegroundColor Green
                                    }
                                    3010 { 
                                        Write-Host "  Installation successful. Reboot required." -ForegroundColor Yellow
                                        $RebootRequired = $true
                                    }
                                    1641 {
                                        Write-Host "  Installation successful. Reboot initiated." -ForegroundColor Yellow
                                        $RebootRequired = $true
                                    }
                                    default { 
                                        Write-Warning "  Exit code: $($Process.ExitCode) (may indicate already updated or minor issue)"
                                    }
                                }
                            }
                        }
                        catch {
                            Write-Warning "  Failed: $_"
                        }
                    }
                    else {
                        Write-Warning "  Could not fetch .NET 9.0 download URLs. Skipping update."
                    }
                }
                else {
                    # For .NET 6.0 LTS and .NET 9.0, keep current behavior
                    Write-Host "  .NET $($version.Split('-')[1]) Desktop Runtime is already installed - Skipping" -ForegroundColor Cyan
                }
            }
        }
        Write-Host ""
    }
    
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Update process completed." -ForegroundColor Green
    
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

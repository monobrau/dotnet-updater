<#
.SYNOPSIS
    Comprehensive updater for all .NET Framework and .NET versions.

.DESCRIPTION
    This comprehensive script scans for and updates ALL major .NET versions:
    - .NET Framework 4.6.2, 4.7, 4.7.1, 4.7.2, 4.8, 4.8.1
    - .NET 6.0 LTS (receives patch updates within 6.x branch)
    - .NET 7.0 (updates to latest .NET 9.0)
    - .NET 8.0 LTS (receives patch updates within 8.x branch)
    - .NET 9.0 (receives patch updates within 9.x branch)

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
    - .NET 6.0 LTS: Receives patch updates (e.g., 6.0.1 → 6.0.x)
    - .NET 7.0: Updates to .NET 9.0 (end of support migration)
    - .NET 8.0 LTS: Receives patch updates (e.g., 8.0.1 → 8.0.x)
    - .NET 9.0: Receives patch updates (e.g., 9.0.0 → 9.0.x)

    Runtime Type Detection:
    - Desktop installations receive Desktop Runtime (includes WPF, WinForms)
    - Server installations (ASP.NET Core only) receive base Runtime
    - Prevents unnecessary Desktop components on servers

    Verbosity:
    - Run with -Verbose for detailed diagnostic output
    - Default output shows only essential information
#>

#Requires -RunAsAdministrator

param(
    [switch]$RemoveOldVersions
)

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
        Write-Verbose "Error reading registry: $_"
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

# Function to uninstall .NET runtime or SDK
function Uninstall-DotNetVersion {
    param(
        [string]$Version,
        [string]$Type  # "Runtime", "Desktop", "AspCore", or "SDK"
    )

    try {
        Write-Verbose "Attempting to uninstall .NET $Version $Type"
        
        # Use Windows Installer to find and uninstall .NET versions
        $uninstallerFound = $false
        
        # Use Get-CimInstance to find installed .NET versions (preferred method)
        try {
            $products = Get-CimInstance -ClassName Win32_Product -Filter "Name LIKE '%Microsoft .NET%$Version%'" -ErrorAction SilentlyContinue
            foreach ($product in $products) {
                if ($product.Name -match "\.NET.*$Version") {
                    Write-Host "  Found installer: $($product.Name)" -ForegroundColor Gray
                    $uninstallerFound = $true
                    Write-Host "  Uninstalling $($product.Name)..." -ForegroundColor Yellow
                    $result = Invoke-CimMethod -InputObject $product -MethodName Uninstall
                    if ($result.ReturnValue -eq 0) {
                        Write-Host "  Successfully uninstalled: $($product.Name)" -ForegroundColor Green
                        return $true
                    }
                    else {
                        Write-Warning "  Uninstall returned code: $($result.ReturnValue)"
                    }
                }
            }
        }
        catch {
            Write-Verbose "Could not query CIM for uninstallers: $_"
            # Fallback to WMI
            try {
                $products = Get-WmiObject -Class Win32_Product -Filter "Name LIKE '%Microsoft .NET%$Version%'" -ErrorAction SilentlyContinue
                foreach ($product in $products) {
                    if ($product.Name -match "\.NET.*$Version") {
                        Write-Host "  Found installer: $($product.Name)" -ForegroundColor Gray
                        $uninstallerFound = $true
                        Write-Host "  Uninstalling $($product.Name)..." -ForegroundColor Yellow
                        $result = $product.Uninstall()
                        if ($result.ReturnValue -eq 0) {
                            Write-Host "  Successfully uninstalled: $($product.Name)" -ForegroundColor Green
                            return $true
                        }
                        else {
                            Write-Warning "  Uninstall returned code: $($result.ReturnValue)"
                        }
                    }
                }
            }
            catch {
                Write-Verbose "Could not query WMI for uninstallers: $_"
            }
        }
        
        if (-not $uninstallerFound) {
            Write-Host "  Warning: Could not find Windows Installer entry for $Version $Type" -ForegroundColor Yellow
            Write-Host "  You may need to uninstall manually via Control Panel > Programs and Features" -ForegroundColor Yellow
        }
        
        return $false
    }
    catch {
        Write-Warning "Error uninstalling .NET $Version $Type: $_"
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

            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
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
        
        # Look for Windows x64 installer - try different property names
        $files = $null
        if ($release.files) {
            $files = $release.files
        }
        elseif ($release.Files) {
            $files = $release.Files
        }
        
        if (-not $files) {
            Write-Verbose "No files found in release $Version"
            return $null
        }
        
        if ($Component -eq "Desktop") {
            $file = $files | Where-Object { 
                ($_.name -match 'windowsdesktop.*runtime' -or $_.Name -match 'windowsdesktop.*runtime') -and 
                ($_.rid -eq 'win-x64' -or $_.Rid -eq 'win-x64') -and 
                ($_.name -match '\.exe$' -or $_.Name -match '\.exe$')
            } | Select-Object -First 1
        }
        elseif ($Component -eq "Runtime") {
            $file = $files | Where-Object { 
                ($_.name -match 'dotnet.*runtime' -or $_.Name -match 'dotnet.*runtime') -and 
                ($_.name -notmatch 'desktop' -and $_.Name -notmatch 'desktop') -and
                ($_.rid -eq 'win-x64' -or $_.Rid -eq 'win-x64') -and 
                ($_.name -match '\.exe$' -or $_.Name -match '\.exe$')
            } | Select-Object -First 1
        }
        else {
            $file = $files | Where-Object { 
                ($_.name -match 'dotnet.*sdk' -or $_.Name -match 'dotnet.*sdk') -and 
                ($_.rid -eq 'win-x64' -or $_.Rid -eq 'win-x64') -and 
                ($_.name -match '\.exe$' -or $_.Name -match '\.exe$')
            } | Select-Object -First 1
        }
        
        if ($file) {
            $downloadUrl = $file.url -or $file.Url -or $file.downloadUrl -or $file.DownloadUrl
            if ($downloadUrl) {
                Write-Verbose "Found download URL in releases.json: $downloadUrl"
                return $downloadUrl
            }
            else {
                Write-Verbose "File found but no URL property: $(($file | Get-Member -MemberType NoteProperty | Select-Object -First 5).Name -join ', ')"
            }
        }
        else {
            Write-Verbose "No matching file found for Component=$Component, RID=win-x64 in release $Version"
            Write-Verbose "Available files: $(($files | Select-Object -First 3 | ForEach-Object { $_.name -or $_.Name }) -join ', ')"
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
        [string]$Component = "Desktop"  # Runtime, Desktop, or SDK
    )

    $maxRetries = 3
    $attempt = 0
    $delay = 2

    while ($attempt -lt $maxRetries) {
        try {
            $attempt++
            Write-Verbose "Fetching download URL attempt $attempt of $maxRetries"
            Write-Host "  Attempt ${attempt} of ${maxRetries}: Getting download URL for .NET ${MajorVersion}.0 ${Component}..." -ForegroundColor Gray

            # First, try to get the latest version from the API
            Write-Verbose "Getting latest version for .NET $MajorVersion.0 from Microsoft API..."
            Write-Host "  Querying Microsoft API for latest version..." -ForegroundColor Gray
            $latestVersion = Get-DotNetLatestVersion -MajorVersion $MajorVersion
            
            if ($latestVersion) {
                Write-Host "  API returned latest version: $latestVersion" -ForegroundColor Green
                Write-Verbose "Found latest version: $latestVersion"
                Write-Host "  Latest available version: $latestVersion" -ForegroundColor Gray
                
                # First, try to get URL directly from releases.json (most reliable)
                Write-Verbose "Attempting to get download URL from releases.json API..."
                Write-Host "  Trying releases.json API method..." -ForegroundColor Gray
                $directUrl = Get-DotNetDownloadUrlFromReleases -MajorVersion $MajorVersion -Component $Component -Version $latestVersion
                
                if ($directUrl) {
                    Write-Verbose "Successfully got download URL from releases.json: $directUrl"
                    Write-Host "  Download URL retrieved successfully" -ForegroundColor Green
                    return $directUrl
                }
                else {
                    Write-Verbose "releases.json API method returned no URL"
                    Write-Host "  releases.json API method failed, trying redirect..." -ForegroundColor Gray
                }
                
                # Fallback: Try redirect following from thank-you page
                Write-Verbose "releases.json method failed, trying redirect following..."
                Write-Host "  Attempting redirect resolution..." -ForegroundColor Gray
                
                # Construct the thank-you page URL (these redirect to actual downloads)
                $thankYouUrl = if ($Component -eq "Desktop") {
                    "https://dotnet.microsoft.com/en-us/download/dotnet/thank-you/runtime-desktop-$latestVersion-windows-x64-installer"
                } elseif ($Component -eq "Runtime") {
                    "https://dotnet.microsoft.com/en-us/download/dotnet/thank-you/runtime-$latestVersion-windows-x64-installer"
                } else {
                    "https://dotnet.microsoft.com/en-us/download/dotnet/thank-you/sdk-$latestVersion-windows-x64-installer"
                }
                
                Write-Verbose "Thank-you URL: $thankYouUrl"
                
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
                        Write-Host "  Download URL resolved successfully" -ForegroundColor Green
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
                                    Write-Host "  Download URL resolved successfully" -ForegroundColor Green
                                    return $finalUrl
                                }
                            }
                            catch {
                                Write-Verbose "Could not follow intermediate redirect: $_"
                            }
                        }
                        Write-Host "  Redirect resolution failed - URL doesn't match expected pattern" -ForegroundColor Yellow
                    }
                }
                else {
                    Write-Verbose "No URL resolved from redirect"
                    Write-Host "  Redirect resolution failed - no URL returned" -ForegroundColor Yellow
                }
            }
            else {
                Write-Verbose "Could not get latest version from API, falling back to HTML scraping"
                Write-Host "  API did not return a version (may be offline or version not found)" -ForegroundColor Yellow
                Write-Host "  Falling back to HTML scraping method..." -ForegroundColor Gray
            }
            
            # Fallback: Try scraping the download page
            Write-Verbose "Falling back to HTML scraping method"
            Write-Host "  Attempting HTML scraping fallback..." -ForegroundColor Gray
            $downloadPage = "https://dotnet.microsoft.com/en-us/download/dotnet/$MajorVersion.0"
            try {
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
            # Add the highest available newer version for update
            $targetVersion = $newerVersions | Select-Object -First 1
            $targetInfo = $DotNetVersions[$targetVersion]

            Write-Host "Newer .NET Framework version available: $($targetInfo.TargetVersion) (Release: $($targetInfo.MinRelease))" -ForegroundColor Yellow

            $installedVersions[$targetVersion] = @{
                Installed = $false  # Not installed yet
                CurrentReleaseValue = $releaseValue
                TargetReleaseValue = $targetInfo.MinRelease
                CurrentVersion = $DotNetVersions[$currentFrameworkVersion].TargetVersion
                TargetVersion = $targetInfo.TargetVersion
                IsFramework = $true
                NeedsUpdate = $true
            }
            $updateCount++
        } else {
            Write-Host ".NET Framework is up to date ($($DotNetVersions[$currentFrameworkVersion].TargetVersion))" -ForegroundColor Green
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
        $aspCoreMatch = $dotnetInfo.Runtimes | Where-Object { $_ -match "Microsoft\.AspNetCore\.App $majorVersion\." }
        $sdkMatch = $dotnetInfo.SDKs | Where-Object { $_ -match "^$majorVersion\." }
        
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
        if ($installed.NeedsUpdate) {
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
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "Beginning updates..." -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Temporary directory for downloads
$TempDir = $env:TEMP
$RebootRequired = $false
$downloadedFiles = @()
$dotNet9InstalledThisSession = $false  # Track if .NET 9 was installed to prevent duplicate installations

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
        else {
            # .NET (Core/5+) update logic
            Write-Host "[$currentUpdate/$($installedVersions.Count)] Checking .NET $($version.Split('-')[1])..." -ForegroundColor Cyan
            
            # Extract current version from installed info - check Desktop, ASP.NET Core, or Runtime
            $currentVersion = $null
            if ($installed.Desktop) {
                $versionMatch = $installed.Desktop -match "(\d+\.\d+\.\d+)"
                if ($versionMatch) {
                    $currentVersion = $matches[1]
                }
            }
            elseif ($installed.AspCore) {
                $versionMatch = $installed.AspCore -match "(\d+\.\d+\.\d+)"
                if ($versionMatch) {
                    $currentVersion = $matches[1]
                }
            }
            elseif ($installed.Runtime) {
                $versionMatch = $installed.Runtime -match "(\d+\.\d+\.\d+)"
                if ($versionMatch) {
                    $currentVersion = $matches[1]
                }
            }
            
            if ($currentVersion) {
                Write-Host "  Current .NET $($version.Split('-')[1]) version: $currentVersion" -ForegroundColor Gray
                
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
                    # Check if .NET 9 is already installed or was installed this session
                    $dotnet9Installed = $installedVersions.Keys | Where-Object { $_ -match "NET-9\.0" }

                    if ($dotnet9Installed -or $dotNet9InstalledThisSession) {
                        Write-Host "  .NET 9.0 is already installed - Skipping upgrade from .NET $majorVersion" -ForegroundColor Cyan
                        continue
                    }
                    
                    Write-Host "  .NET $($version.Split('-')[1]) detected - updating to latest .NET 9.x..." -ForegroundColor Yellow

                    # Determine which component to download based on what's installed
                    # Priority: Desktop (includes Runtime) > AspCore (includes Runtime) > Runtime
                    $componentToInstall = if ($installed.Desktop) {
                        "Desktop"
                    } elseif ($installed.AspCore) {
                        "Runtime"  # For server scenarios, install base Runtime instead of Desktop
                    } else {
                        "Runtime"
                    }

                    Write-Host "  Detected runtime type: $componentToInstall" -ForegroundColor Gray

                    # Get the download URL dynamically from Microsoft
                    Write-Host "  Getting download URL from Microsoft..." -ForegroundColor Gray
                    $url = Get-DotNetDownloadUrl -MajorVersion 9 -Component $componentToInstall

                    if (-not $url) {
                        Write-Warning "  Could not get download URL. Skipping update."
                        continue
                    }

                    Write-Host "  Download URL: $url" -ForegroundColor Gray
                    $installerPath = Join-Path $TempDir "dotnet-9.0-$($componentToInstall.ToLower()).exe"
                    $downloadedFiles += $installerPath
                    
                    try {
                        $componentDisplayName = if ($componentToInstall -eq "Desktop") { "Desktop Runtime" } else { "Runtime" }
                        Write-Host "  Downloading latest .NET 9.0 $componentDisplayName..."
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
                            # Check installer version
                            $installerVersion = Get-InstallerVersion -FilePath $installerPath
                            if ($installerVersion) {
                                Write-Host "  Downloaded installer version: $installerVersion" -ForegroundColor Gray
                            }

                            Write-Host "  Installing .NET 9.0 $componentDisplayName..."
                            $silentArgs = $SilentArgsMap["NET"]
                            $Process = Start-Process -FilePath $installerPath -ArgumentList $silentArgs -Wait -PassThru -WindowStyle Hidden
                            
                            switch ($Process.ExitCode) {
                                0 {
                                    Write-Host "  Installation successful." -ForegroundColor Green
                                    $dotNet9InstalledThisSession = $true
                                }
                                3010 {
                                    Write-Host "  Installation successful. Reboot required." -ForegroundColor Yellow
                                    $RebootRequired = $true
                                    $dotNet9InstalledThisSession = $true
                                }
                                1641 {
                                    Write-Host "  Installation successful. Reboot initiated." -ForegroundColor Yellow
                                    $RebootRequired = $true
                                    $dotNet9InstalledThisSession = $true
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
                    # For .NET 6.0, 8.0 (LTS) and 9.0, check for patch updates
                    $majorVersion = [int]$version.Split('-')[1].Split('.')[0]

                    Write-Host "  Checking for .NET $majorVersion.0 patch updates..." -ForegroundColor Gray

                    # First, check if we're already on the latest version
                    Write-Host "  Querying Microsoft API for latest version..." -ForegroundColor Gray
                    $latestVersion = Get-DotNetLatestVersion -MajorVersion $majorVersion
                    
                    if ($latestVersion) {
                        Write-Host "  Latest available version: $latestVersion" -ForegroundColor Gray
                        Write-Host "  Current installed version: $currentVersion" -ForegroundColor Gray
                        
                        # Compare versions - if we're already up to date, skip
                        if (Compare-Version -CurrentVersion $currentVersion -TargetVersion $latestVersion) {
                            Write-Host "  .NET $majorVersion.0 is already up to date - Skipping" -ForegroundColor Cyan
                            continue
                        }
                        else {
                            Write-Host "  Update available: $currentVersion -> $latestVersion" -ForegroundColor Yellow
                        }
                    }
                    else {
                        Write-Host "  Could not determine latest version from API, proceeding with download check..." -ForegroundColor Yellow
                    }

                    # Determine which component to download based on what's installed
                    $componentToInstall = if ($installed.Desktop) {
                        "Desktop"
                    } elseif ($installed.AspCore) {
                        "Runtime"
                    } else {
                        "Runtime"
                    }

                    # Get the latest download URL
                    $url = Get-DotNetDownloadUrl -MajorVersion $majorVersion -Component $componentToInstall

                    if (-not $url) {
                        Write-Host "  Could not get download URL. Skipping update check." -ForegroundColor Gray
                        continue
                    }

                    # Download to temp location to check version
                    $tempInstallerPath = Join-Path $TempDir "dotnet-$majorVersion.0-$($componentToInstall.ToLower())-check.exe"

                    try {
                        Write-Host "  Downloading latest version info..." -ForegroundColor Gray
                        Invoke-WebRequestWithRetry -Uri $url -OutFile $tempInstallerPath

                        # Validate downloaded file
                        if (-not (Test-DownloadedFile -FilePath $tempInstallerPath -MinimumSizeBytes 1048576)) {
                            Write-Warning "  Downloaded file validation failed. Skipping update check."
                            if (Test-Path $tempInstallerPath) {
                                Remove-Item -Path $tempInstallerPath -Force -ErrorAction SilentlyContinue
                            }
                            continue
                        }

                        if (Test-Path $tempInstallerPath) {
                            # Check installer version
                            $latestVersion = Get-InstallerVersion -FilePath $tempInstallerPath

                            if ($latestVersion) {
                                Write-Host "  Latest available version: $latestVersion" -ForegroundColor Gray
                                Write-Host "  Current installed version: $currentVersion" -ForegroundColor Gray

                                # Compare versions
                                if (Compare-Version -CurrentVersion $currentVersion -TargetVersion $latestVersion) {
                                    Write-Host "  .NET $majorVersion.0 is already up to date - Skipping" -ForegroundColor Cyan
                                    Remove-Item -Path $tempInstallerPath -Force -ErrorAction SilentlyContinue
                                } else {
                                    Write-Host "  Update available: $currentVersion -> $latestVersion" -ForegroundColor Yellow

                                    # Rename temp file to final installer path
                                    $installerPath = Join-Path $TempDir "dotnet-$majorVersion.0-$($componentToInstall.ToLower()).exe"
                                    Move-Item -Path $tempInstallerPath -Destination $installerPath -Force
                                    $downloadedFiles += $installerPath

                                    $componentDisplayName = if ($componentToInstall -eq "Desktop") { "Desktop Runtime" } else { "Runtime" }
                                    Write-Host "  Installing .NET $majorVersion.0 $componentDisplayName ($latestVersion)..."
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
                            } else {
                                Write-Host "  Could not determine installer version - Skipping" -ForegroundColor Gray
                                Remove-Item -Path $tempInstallerPath -Force -ErrorAction SilentlyContinue
                            }
                        }
                    }
                    catch {
                        Write-Warning "  Failed to check for updates: $_"
                        if (Test-Path $tempInstallerPath) {
                            Remove-Item -Path $tempInstallerPath -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
            else {
                Write-Host "  .NET $($version.Split('-')[1]) is installed but no update needed" -ForegroundColor Cyan
            }
        }
        Write-Host ""
    }
    
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "Update process completed." -ForegroundColor Green
    
    # Check if we should remove old versions
    if ($RemoveOldVersions) {
        Write-Host ""
        Write-Host "=============================================" -ForegroundColor Cyan
        Write-Host "Checking for old .NET versions to remove..." -ForegroundColor Cyan
        Write-Host "=============================================" -ForegroundColor Cyan
        Write-Host ""
        
        # Check if .NET 9 is installed
        $dotnetInfo = Get-InstalledDotNetVersions
        $dotnet9Installed = $false
        
        if ($dotnetInfo.Available) {
            $dotnet9Runtimes = $dotnetInfo.Runtimes | Where-Object { $_ -match "Microsoft\.NETCore\.App 9\." -or $_ -match "Microsoft\.WindowsDesktop\.App 9\." }
            if ($dotnet9Runtimes) {
                $dotnet9Installed = $true
                Write-Host ".NET 9.0 is installed. Checking for older versions to remove..." -ForegroundColor Green
                Write-Host ""
            }
        }
        
        if ($dotnet9Installed) {
            $versionsToRemove = @()
            
            # Check for .NET 6, 7, and 8
            foreach ($runtime in $dotnetInfo.Runtimes) {
                if ($runtime -match "Microsoft\.NETCore\.App (6|7|8)\.\d+\.\d+") {
                    $versionMatch = $runtime -match "Microsoft\.NETCore\.App (\d+\.\d+\.\d+)"
                    if ($versionMatch) {
                        $version = $matches[1]
                        $majorVersion = [int]$version.Split('.')[0]
                        if ($majorVersion -ge 6 -and $majorVersion -le 8) {
                            $versionsToRemove += @{
                                Version = $version
                                Type = "Runtime"
                                FullName = $runtime
                            }
                        }
                    }
                }
                if ($runtime -match "Microsoft\.WindowsDesktop\.App (6|7|8)\.\d+\.\d+") {
                    $versionMatch = $runtime -match "Microsoft\.WindowsDesktop\.App (\d+\.\d+\.\d+)"
                    if ($versionMatch) {
                        $version = $matches[1]
                        $majorVersion = [int]$version.Split('.')[0]
                        if ($majorVersion -ge 6 -and $majorVersion -le 8) {
                            $versionsToRemove += @{
                                Version = $version
                                Type = "Desktop"
                                FullName = $runtime
                            }
                        }
                    }
                }
                if ($runtime -match "Microsoft\.AspNetCore\.App (6|7|8)\.\d+\.\d+") {
                    $versionMatch = $runtime -match "Microsoft\.AspNetCore\.App (\d+\.\d+\.\d+)"
                    if ($versionMatch) {
                        $version = $matches[1]
                        $majorVersion = [int]$version.Split('.')[0]
                        if ($majorVersion -ge 6 -and $majorVersion -le 8) {
                            $versionsToRemove += @{
                                Version = $version
                                Type = "AspCore"
                                FullName = $runtime
                            }
                        }
                    }
                }
            }
            
            # Check for SDKs
            foreach ($sdk in $dotnetInfo.SDKs) {
                if ($sdk -match "^([678])\.\d+\.\d+") {
                    $versionMatch = $sdk -match "^(\d+\.\d+\.\d+)"
                    if ($versionMatch) {
                        $version = $matches[1]
                        $versionsToRemove += @{
                            Version = $version
                            Type = "SDK"
                            FullName = $sdk
                        }
                    }
                }
            }
            
            if ($versionsToRemove.Count -gt 0) {
                Write-Host "Found $($versionsToRemove.Count) older .NET version(s) to remove:" -ForegroundColor Yellow
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
                
                Write-Host "Removed $removedCount of $($versionsToRemove.Count) older .NET version(s)." -ForegroundColor $(if ($removedCount -eq $versionsToRemove.Count) { "Green" } else { "Yellow" })
            }
            else {
                Write-Host "No older .NET versions (6, 7, or 8) found to remove." -ForegroundColor Green
            }
        }
        else {
            Write-Host ".NET 9.0 is not installed. Skipping removal of older versions." -ForegroundColor Yellow
            Write-Host "Note: Only removing older versions when .NET 9.0 is present." -ForegroundColor Gray
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

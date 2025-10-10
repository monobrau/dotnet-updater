# .NET Runtime Updater

A comprehensive PowerShell script that automatically updates .NET Runtime, Desktop Runtime, and SDK installations on Windows systems.

## Features

- **Automatic Detection** - Scans for installed .NET versions
- **Multiple Runtime Types** - Handles .NET Runtime, Desktop Runtime, and SDK
- **Version Support** - .NET 6, 7, 8, 9 and .NET Framework 4.8.1
- **Smart Updates** - Only downloads and installs what's needed
- **Silent Operation** - Runs without user interaction
- **RMM/ScreenConnect Compatible** - Multiple output modes for automation tools
- **Architecture Support** - Handles both x64 and x86 installations

## Supported Versions

### .NET Core / .NET (Modern)
- ✅ .NET 6.0 (LTS - Long Term Support)
- ✅ .NET 7.0
- ✅ .NET 8.0 (LTS - Long Term Support)
- ✅ .NET 9.0 (Current)

### .NET Framework (Legacy)
- ✅ .NET Framework 4.8.1

## Scripts

### dotnet-updater.ps1
The main updater script with full detailed output.

```powershell
.\dotnet-updater.ps1
```

### dotnet-updater-silent.ps1
Wrapper with minimal output suitable for RMM tools. Saves full log to temp directory.

```powershell
.\dotnet-updater-silent.ps1
```

### dotnet-updater-screenconnect.ps1
Compact output specifically formatted for ConnectWise ScreenConnect commands.

```powershell
.\dotnet-updater-screenconnect.ps1
```

## Usage

### Standard Usage
```powershell
# Run the main script
.\dotnet-updater.ps1
```

### ScreenConnect Command (Recommended)
```powershell
#!ps
#maxlength=200000
#timeout=300000
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
New-Item -Path "C:\temp" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
(New-Object Net.WebClient).DownloadFile("https://raw.githubusercontent.com/monobrau/dotnet-updater/main/dotnet-updater.ps1", "C:\temp\dotnet-updater.ps1")
& "C:\temp\dotnet-updater.ps1"
```

### ScreenConnect with Compact Output
```powershell
#!ps
#maxlength=200000
#timeout=300000
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
New-Item -Path "C:\temp" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
(New-Object Net.WebClient).DownloadFile("https://raw.githubusercontent.com/monobrau/dotnet-updater/main/dotnet-updater-screenconnect.ps1", "C:\temp\dotnet-updater-screenconnect.ps1")
(New-Object Net.WebClient).DownloadFile("https://raw.githubusercontent.com/monobrau/dotnet-updater/main/dotnet-updater.ps1", "C:\temp\dotnet-updater.ps1")
& "C:\temp\dotnet-updater-screenconnect.ps1"
```

## Requirements

- Windows PowerShell 5.1 or later
- Administrative privileges (for installation)
- Internet connection (to download updates)
- Supported OS: Windows 10/11, Windows Server 2016+

## How It Works

1. **Detection Phase**
   - Checks if `dotnet` command is available
   - Enumerates installed runtimes and SDKs
   - Detects both modern .NET and .NET Framework versions

2. **Version Checking**
   - Queries latest available versions from Microsoft
   - Compares installed versions with available updates
   - Determines which runtimes need installation

3. **Update Phase**
   - Downloads only necessary installers from official Microsoft sources
   - Installs silently without user interaction
   - Handles both x64 and x86 architectures
   - Cleans up temporary files

4. **Reporting**
   - Shows detection results with color coding
   - Displays update status for each runtime
   - Reports success/failure with exit codes

## Runtime Types

### .NET Runtime
Core runtime for running .NET applications. Required for most .NET apps.

### ASP.NET Core Runtime
Specialized runtime for web applications and services.

### .NET Desktop Runtime
Includes Windows Desktop components (WPF, Windows Forms). Required for desktop applications.

### .NET SDK
Full development kit including compiler, tools, and runtimes. Required for development.

## Example Output

```
=============================================
.NET All Versions Updater
=============================================

Checking for dotnet availability...
dotnet command is available.

Checking installed .NET versions...

=============================================
Detection Results
=============================================

.NET Runtime 8.0 [LTS]:
  Runtime: 8.0.1
  Desktop Runtime: 8.0.1
  Status: Updates available

.NET Framework 4.8.1:
  Status: INSTALLED

Total updates to process: 1

=============================================
Beginning updates...
=============================================

Processing .NET Runtime 8.0...
  Downloading latest .NET 8.0 Desktop Runtime (x64)...
  Installing...
  Installation successful.

=============================================
Update process completed.
=============================================
```

## Exit Codes

- `0` - Success, no updates needed or all updates completed
- `1` - Error occurred during update process
- `3010` - Success, reboot required

## Security

- All downloads are from official Microsoft servers
- No third-party hosting or modified installers
- Downloads use HTTPS
- File version verification included

## Troubleshooting

### "dotnet command not found"
- This is normal if no .NET is installed
- Script will install the runtimes from scratch

### Downloads failing
- Check internet connection
- Verify Microsoft download URLs are accessible
- Check if antivirus is blocking downloads
- Ensure TLS 1.2 is enabled

### Installation fails silently
- Check if you have administrative privileges
- Look for conflicts with existing installations
- Check Windows Event Viewer for detailed errors

## ScreenConnect Tips

- `#timeout=300000` = 5 minutes (increase for slow connections)
- `#maxlength=200000` = captures up to 200KB of output
- TLS 1.2 line is critical for GitHub/Microsoft downloads
- Wait 2-5 minutes for scripts with downloads/installations
- .NET installers can be large (50-200MB), be patient

## License

MIT License - Feel free to use and modify

## Author

Created for system administrators managing Windows environments

## Contributing

Contributions welcome! Please test thoroughly before submitting pull requests.

## Changelog

### v1.0 (2024-10-10)
- Initial release
- Support for .NET 6, 7, 8, 9
- Support for .NET Framework 4.8.1
- ScreenConnect compatibility
- Multiple output modes


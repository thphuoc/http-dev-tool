<#
Helper script to (1) elevate, (2) enable Developer Mode (registry),
(3) run flutter pub get, flutter doctor, flutter analyze, and flutter run -d windows.

Usage:
  - To create and run: right-click -> Run with PowerShell or execute from PowerShell.
  - The script will relaunch itself as Administrator if needed (UAC prompt).

Caveats: enabling Developer Mode via the registry may require sign-out/reboot in some environments.
#>

param(
    [switch]$RunNow
)

function Is-Administrator {
    $current = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$scriptPath = $MyInvocation.MyCommand.Definition

if (-not (Is-Administrator)) {
    Write-Output "Not running as administrator. Relaunching elevated..."
    Start-Process -FilePath "powershell" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","`"$scriptPath`"","-RunNow" -Verb RunAs
    exit
}

Write-Output "Running elevated setup (this window is Administrator)."

# 1) Enable Developer Mode via registry (Allow symlinks for dev)
try {
    Write-Output "Enabling Developer Mode in registry..."
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v AllowDevelopmentWithoutDevLicense /d 1 | Out-Null
    Write-Output "Registry updated."
} catch {
    Write-Output "Failed to update registry: $_"
}

# 2) Change to project directory
$proj = "d:\\phuoc\\projects\\flutter-http-dev-tool\\httpdevtool"
Set-Location -LiteralPath $proj
Write-Output "Changed directory to $proj"

# 3) Fetch packages
Write-Output "Running: flutter pub get --no-analytics"
flutter pub get --no-analytics

# 4) Run diagnostics
Write-Output "Running: flutter doctor -v"
flutter doctor -v

# 5) Analyze
Write-Output "Running: flutter analyze"
flutter analyze

# 6) Run the app on Windows
Write-Output "Running: flutter run -d windows"
flutter run -d windows

Write-Output "Script finished."

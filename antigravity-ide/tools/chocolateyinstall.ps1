$ErrorActionPreference = 'Stop'

# Per-architecture installers. Kept in sync by ../update.ps1 (AU).
$url64         = 'https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.0.4-6381998290370560/windows-x64/Antigravity%20IDE.exe'
$checksum64    = 'c4a83fe97ca159d9e67f4908955526ab6eb03fc747cab4af1a8d05f803e3bc6d'
$urlArm64      = 'https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.0.4-6381998290370560/windows-arm64/Antigravity%20IDE.exe'
$checksumArm64 = '3c82ae95de2643b47576409f58b5e07aa352d02e52e4d5ddd9a3e7cd0dcb59e4'

# Detect ARM64 even when Chocolatey runs as an x64 (emulated) process on ARM hardware.
$isArm64 = ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') -or ($env:PROCESSOR_ARCHITEW6432 -eq 'ARM64')

$packageArgs = @{
  packageName    = $env:ChocolateyPackageName
  fileType       = 'exe'
  url            = if ($isArm64) { $urlArm64 }      else { $url64 }
  checksum       = if ($isArm64) { $checksumArm64 } else { $checksum64 }
  checksumType   = 'sha256'
  softwareName   = 'Antigravity IDE*'
  # InnoSetup silent switches.
  silentArgs     = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
  validExitCodes = @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs

# The installer auto-launches the IDE even in silent mode; close it so an
# unattended `choco install` finishes cleanly. Best-effort, non-fatal.
$timeout = 60
$timer = [System.Diagnostics.Stopwatch]::StartNew()
while ($timer.Elapsed.TotalSeconds -lt $timeout) {
  if (Get-Process -Name 'Antigravity*' -ErrorAction SilentlyContinue) {
    Start-Sleep -Seconds 5
    Stop-Process -Name 'Antigravity*' -Force -ErrorAction SilentlyContinue
    break
  }
  Start-Sleep -Seconds 1
}

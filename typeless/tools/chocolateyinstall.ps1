$ErrorActionPreference = 'Stop'

# Per-architecture installers. Kept in sync by ../update.ps1 (AU).
# The checksums are the sha512 digests published in upstream's own electron-builder
# update feeds (latest.yml / arm64.yml) - the same ones the app's updater verifies.
$url64         = 'https://typeless-static.com/desktop-release/Typeless-2.8.3-x64-Setup.exe'
$checksum64    = '0fc1de2606d49684f73baff3bdfd66ce8a6da166c7f83f1e81fbbe5e7831d4cf18fa46227c6452212bdc9bb80c6aa9c3169969e2612542da4637dabac516cf3a'
$urlArm64      = 'https://typeless-static.com/desktop-release/Typeless-2.8.3-arm64-Setup.exe'
$checksumArm64 = 'f3bd9e915724257b0ec336fc5150e105742f7f13a75f47f3f7986d3038489b4a2bbbabe4fc1eefdf710573977a6eae3ab15065c29534ae892d80008cf1bfa8d4'

# Detect ARM64 even when Chocolatey runs as an x64 (emulated) process on ARM hardware.
$isArm64 = ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') -or ($env:PROCESSOR_ARCHITEW6432 -eq 'ARM64')

$packageArgs = @{
  packageName    = $env:ChocolateyPackageName
  fileType       = 'exe'
  url            = if ($isArm64) { $urlArm64 }      else { $url64 }
  checksum       = if ($isArm64) { $checksumArm64 } else { $checksum64 }
  checksumType   = 'sha512'
  softwareName   = 'Typeless*'
  # NSIS (electron-builder) silent switch.
  silentArgs     = '/S'
  validExitCodes = @(0)
}

Install-ChocolateyPackage @packageArgs

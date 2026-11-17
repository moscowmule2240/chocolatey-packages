$ErrorActionPreference = 'Stop'

# Per-architecture installers. Kept in sync by ../update.ps1 (AU).
# The checksums are the sha512 digests published in upstream's own electron-builder
# update feeds (latest.yml / arm64.yml) - the same ones the app's updater verifies.
$url64         = 'https://typeless-static.com/desktop-release/Typeless-2.12.0-x64-Setup.exe'
$checksum64    = '53fd7684fe69c7a1b7623f14d943d07b165b53314510bcdbe35e90c081e22a5e957a5201b5bab88dba9090b9e8e5143d317b3cd127ba07a8d845537dfe48ac6d'
$urlArm64      = 'https://typeless-static.com/desktop-release/Typeless-2.12.0-arm64-Setup.exe'
$checksumArm64 = '3c2448c87540596154f51a799bff6b3066eeb14032ce5f662c8b6680d2243fb6a6216da04fad62cceeb2e921f93fdd8864c700e4ddb607c9326e1e23f52af741'

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

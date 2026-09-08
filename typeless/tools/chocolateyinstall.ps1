$ErrorActionPreference = 'Stop'

# Per-architecture installers. Kept in sync by ../update.ps1 (AU).
# The checksums are the sha512 digests published in upstream's own electron-builder
# update feeds (latest.yml / arm64.yml) - the same ones the app's updater verifies.
$url64         = 'https://typeless-static.com/desktop-release/Typeless-2.6.0-x64-Setup.exe'
$checksum64    = '939b103c9c97ce88b903f265efccd08af6fe2330aa394fba7a9078a0e8eec4398cc6036065425970a12d4fa5c6a899b417ae35aa250df1476c7adcc18dc7ae35'
$urlArm64      = 'https://typeless-static.com/desktop-release/Typeless-2.6.0-arm64-Setup.exe'
$checksumArm64 = '6f61774009f2c3fc47f4da700dd5b96be01af0124dfae0b5c010649907a8b6854f569ec86e1153bf08e6bc549b0636e7e549cabc938ece9ab8ea4454f7c8017b'

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

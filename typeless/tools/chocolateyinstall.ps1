$ErrorActionPreference = 'Stop'

# Per-architecture installers. Kept in sync by ../update.ps1 (AU).
# The checksums are the sha512 digests published in upstream's own electron-builder
# update feeds (latest.yml / arm64.yml) - the same ones the app's updater verifies.
$url64         = 'https://typeless-static.com/desktop-release/Typeless-2.7.0-x64-Setup.exe'
$checksum64    = '109c2cfe0ceb9bd0b6f40102ea63a899ec8ad041c5499407fda66dfcec5dd5366a01cdabf80261aeb4315257a22ac200aacfe017c491922336dd5f3bd70101b0'
$urlArm64      = 'https://typeless-static.com/desktop-release/Typeless-2.7.0-arm64-Setup.exe'
$checksumArm64 = '03f2bf1c5bdab2f890c9341a32d603bf54b82349366dc364c80648b4409f1b47443de1a7c77b7c63ab6f17d0d9ab6510070fe0ce0cb91b3da988ac3955792d96'

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

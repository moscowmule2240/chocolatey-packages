$ErrorActionPreference = 'Stop'

# Per-architecture installers. Kept in sync by ../update.ps1 (AU).
# The checksums are the sha512 digests published in upstream's own electron-builder
# update feeds (latest.yml / arm64.yml) - the same ones the app's updater verifies.
$url64         = 'https://typeless-static.com/desktop-release/Typeless-2.8.2-x64-Setup.exe'
$checksum64    = '8d65c71a82c1c666b6955eb823b927a93fb1f139f168f1f500e376c8ab0781f5743eb737c461497ce02cc57f7d8cd4edadbf908aa4af29ea825160bab8e1e17d'
$urlArm64      = 'https://typeless-static.com/desktop-release/Typeless-2.8.2-arm64-Setup.exe'
$checksumArm64 = '3448b00969d662ebd10a3fab451d7179295040d92141832e00aa229b21c76a4f220db30cdaac5bea169a268b5fb8e7577b21872db08e2307440a8f2058ad7d7e'

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

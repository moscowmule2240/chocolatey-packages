$ErrorActionPreference = 'Stop'

# Per-architecture installers. Kept in sync by ../update.ps1 (AU).
# The checksums are the sha512 digests published in upstream's own electron-builder
# update feeds (latest.yml / arm64.yml) - the same ones the app's updater verifies.
$url64         = 'https://typeless-static.com/desktop-release/Typeless-2.8.1-x64-Setup.exe'
$checksum64    = '614512fefb681429a0003fc52667bcef46e9da70dbcffa575c5d7b7d4678a6ebf6c074de2d100f8c7202a3abfe9bfb9a306cd8cb252aa293024adaf70a071b63'
$urlArm64      = 'https://typeless-static.com/desktop-release/Typeless-2.8.1-arm64-Setup.exe'
$checksumArm64 = '535f15a405526984db64979e82adcefeeb8865feac77442500901049c27010dae2061d413b9d3edf73cc317dbad6b835ea6b5bc9e2e4d10686ca627e233760d0'

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

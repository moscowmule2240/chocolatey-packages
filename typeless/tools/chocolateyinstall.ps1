$ErrorActionPreference = 'Stop'

# Per-architecture installers. Kept in sync by ../update.ps1 (AU).
# The checksums are the sha512 digests published in upstream's own electron-builder
# update feeds (latest.yml / arm64.yml) - the same ones the app's updater verifies.
$url64         = 'https://typeless-static.com/desktop-release/Typeless-2.1.0-x64-Setup.exe'
$checksum64    = '0d5c93e538b490f35a743734ea4df061e1fa5616b35687e979248556f8d692f3e16fba9850d981df5481da8e7772386fc4eb98a5d77687ee69a0dd6ac5efce06'
$urlArm64      = 'https://typeless-static.com/desktop-release/Typeless-2.1.0-arm64-Setup.exe'
$checksumArm64 = 'f254892b929e0a10fbc7385c0c7af2d4e35592b7bc2104c8020dedf0196793e17b7c3a40715cdeffa73ffa70782b09b9d3c794ba6df4bf65573d255b094b827c'

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

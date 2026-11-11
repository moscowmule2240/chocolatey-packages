$ErrorActionPreference = 'Stop'

# Per-architecture installers. Kept in sync by ../update.ps1 (AU).
# The checksums are the sha512 digests published in upstream's own electron-builder
# update feeds (latest.yml / arm64.yml) - the same ones the app's updater verifies.
$url64         = 'https://typeless-static.com/desktop-release/Typeless-2.11.0-x64-Setup.exe'
$checksum64    = '6389f0583442cb28d85d9808fc494b7b5c62b4831d077c394eb85f7628dfa8afe6684b668778e2e02b3d3322fecdbdae0a0b15467b6363800e4d589bee317201'
$urlArm64      = 'https://typeless-static.com/desktop-release/Typeless-2.11.0-arm64-Setup.exe'
$checksumArm64 = '1766659d114392abc7f21d2c42e8ac9056c2e2a3a1e50e45b379081cd1833a6c2683bdcf96e3e2973fe784b13f70ad1b6457da8901a6d3816bc1e40c88047629'

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

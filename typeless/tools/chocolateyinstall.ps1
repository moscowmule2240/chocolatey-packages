$ErrorActionPreference = 'Stop'

# Per-architecture installers. Kept in sync by ../update.ps1 (AU).
# The checksums are the sha512 digests published in upstream's own electron-builder
# update feeds (latest.yml / arm64.yml) - the same ones the app's updater verifies.
$url64         = 'https://typeless-static.com/desktop-release/Typeless-2.5.0-x64-Setup.exe'
$checksum64    = '9ab10cc0583ab8b46dc363de8f6987ca780db090e1dd1948b2b03c1684bf5d0048da2c2aaab879c0953d0fae653da0cedd57c9d6c6719fcbdf05afad5d39a44e'
$urlArm64      = 'https://typeless-static.com/desktop-release/Typeless-2.5.0-arm64-Setup.exe'
$checksumArm64 = '804116038a7a73eee60c5c63f285bb1b8fcee03f63fdb8c53ab3818f2034191ec77faa6e3145e60ae64b2d126798df1ffccba8c5c7e1c138d4e895a5e0279570'

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

$ErrorActionPreference = 'Stop'

# Per-architecture installers. Kept in sync by ../update.ps1 (AU).
# The checksums are the sha512 digests published in upstream's own electron-builder
# update feeds (latest.yml / arm64.yml) - the same ones the app's updater verifies.
$url64         = 'https://typeless-static.com/desktop-release/Typeless-2.8.0-x64-Setup.exe'
$checksum64    = 'c46bb2b8b84c8aac79980d17bdc4f61434501ce6568048cfe619ab3f7e155c5e3e1ea113a5e0fd1f5cfde7741be56e736ce6636bec6c761311b9f73dbcb8a507'
$urlArm64      = 'https://typeless-static.com/desktop-release/Typeless-2.8.0-arm64-Setup.exe'
$checksumArm64 = '23c16a267a4c9a350d5b211fe35e19a3193ef0165899348c0728a42831592042c08aed806dd7b5727f69687d15497b1688d38c08bb1713a778b16be0c9092b4f'

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

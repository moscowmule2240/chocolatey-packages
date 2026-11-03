$ErrorActionPreference = 'Stop'

# Per-architecture installers. Kept in sync by ../update.ps1 (AU).
# The checksums are the sha512 digests published in upstream's own electron-builder
# update feeds (latest.yml / arm64.yml) - the same ones the app's updater verifies.
$url64         = 'https://typeless-static.com/desktop-release/Typeless-2.10.0-x64-Setup.exe'
$checksum64    = '9bbc03bb61642d83e21a4246681cf78440ecaf71ec4b055b75b3afed80ca61e13ba5c3bc43591f735c42c6a8b386241c32c764efb447ad2593797ba9c8553eda'
$urlArm64      = 'https://typeless-static.com/desktop-release/Typeless-2.10.0-arm64-Setup.exe'
$checksumArm64 = '9c9fbd4b0ad7ffd58e8a3079c35b49a75676d3331e4e2081ee383538fa69e470b504c4b6812f19d75f77c476529668e9ee92d805bf947a1743e7f19d48a8aaa3'

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

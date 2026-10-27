$ErrorActionPreference = 'Stop'

# Per-architecture installers. Kept in sync by ../update.ps1 (AU).
# The checksums are the sha512 digests published in upstream's own electron-builder
# update feeds (latest.yml / arm64.yml) - the same ones the app's updater verifies.
$url64         = 'https://typeless-static.com/desktop-release/Typeless-2.9.0-x64-Setup.exe'
$checksum64    = 'e60125de739d814287daf9b865c7e093d13e43182bd670dde8758771b3187beded6b4ffa4039f87ee8293f68547c0c7b877c2a996a536f6e946e479c87a98547'
$urlArm64      = 'https://typeless-static.com/desktop-release/Typeless-2.9.0-arm64-Setup.exe'
$checksumArm64 = 'b3b54a118bd831debece70c3383abe59b8d3576fee4e5b5cf499d76f130961b8751c3290babccc8859853c508945cc322001334d84bbf145d86e8f3bcf6b0a64'

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

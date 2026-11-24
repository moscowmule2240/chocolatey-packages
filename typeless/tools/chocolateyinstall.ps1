$ErrorActionPreference = 'Stop'

# Per-architecture installers. Kept in sync by ../update.ps1 (AU).
# The checksums are the sha512 digests published in upstream's own electron-builder
# update feeds (latest.yml / arm64.yml) - the same ones the app's updater verifies.
$url64         = 'https://typeless-static.com/desktop-release/Typeless-2.13.0-x64-Setup.exe'
$checksum64    = '25a01bd56a8cf28ab7a78c8e4dbb11cb9845a310748f014ec995a6bff14f6f47a83b115440a5c85e916ea148d7a84413baa433b155d651b10e1496665589435a'
$urlArm64      = 'https://typeless-static.com/desktop-release/Typeless-2.13.0-arm64-Setup.exe'
$checksumArm64 = '227ca93b62a3d658c89003de30cb115390003246149c7cb9655134c5b5c873da490199e6fde4432a8c5c44812c247845aa02263e71018b2b60aa8fb57012a871'

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

$ErrorActionPreference = 'Stop'

$packageName  = $env:ChocolateyPackageName
$softwareName = 'Typeless*'

# electron-builder's NSIS installer registers its uninstall entry under HKCU when
# it installs per-user and under HKLM when it installs per-machine.
# Get-UninstallRegistryKey searches both, so this works either way.
[array]$key = Get-UninstallRegistryKey -SoftwareName $softwareName

if ($key.Count -eq 1) {
  $key | ForEach-Object {
    $packageArgs = @{
      packageName    = $packageName
      fileType       = 'exe'
      # NSIS uninstaller (Uninstall Typeless.exe); strip surrounding quotes.
      file           = ($_.UninstallString -replace '"', '')
      silentArgs     = '/S'
      validExitCodes = @(0)
    }
    Uninstall-ChocolateyPackage @packageArgs
  }
} elseif ($key.Count -eq 0) {
  Write-Warning "$packageName has already been uninstalled."
} elseif ($key.Count -gt 1) {
  Write-Warning "$($key.Count) matches found for '$softwareName' - skipping auto-uninstall."
  $key | ForEach-Object { Write-Warning "- $($_.DisplayName)" }
}

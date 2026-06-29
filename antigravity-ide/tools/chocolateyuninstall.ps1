$ErrorActionPreference = 'Stop'

$packageName  = $env:ChocolateyPackageName
$softwareName = 'Antigravity IDE*'

[array]$key = Get-UninstallRegistryKey -SoftwareName $softwareName

if ($key.Count -eq 1) {
  $key | ForEach-Object {
    $packageArgs = @{
      packageName    = $packageName
      fileType       = 'exe'
      # InnoSetup uninstaller (unins000.exe); strip surrounding quotes.
      file           = ($_.UninstallString -replace '"', '')
      silentArgs     = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
      validExitCodes = @(0, 3010, 1605, 1614, 1641)
    }
    Uninstall-ChocolateyPackage @packageArgs
  }
} elseif ($key.Count -eq 0) {
  Write-Warning "$packageName has already been uninstalled."
} elseif ($key.Count -gt 1) {
  Write-Warning "$($key.Count) matches found for '$softwareName' - skipping auto-uninstall."
  $key | ForEach-Object { Write-Warning "- $($_.DisplayName)" }
}

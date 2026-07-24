$ErrorActionPreference = 'Stop'

$packageName  = $env:ChocolateyPackageName
$softwareName = 'Typeless*'

# electron-builder's NSIS installer registers its uninstall entry under HKCU when
# it installs per-user and under HKLM when it installs per-machine.
# Get-UninstallRegistryKey searches both, so this works either way.
[array]$key = Get-UninstallRegistryKey -SoftwareName $softwareName

if ($key.Count -eq 1) {
  $key | ForEach-Object {
    # A per-user install records its uninstaller WITH a trailing argument:
    #   "C:\Users\<u>\AppData\Local\Programs\Typeless\Uninstall Typeless.exe" /currentuser
    # so the quotes cannot simply be stripped - that folds "/currentuser" into the
    # path and yields a file name that does not exist. Split the quoted executable
    # from its arguments and pass them separately; /currentuser is what tells the
    # uninstaller to remove the per-user installation.
    $uninstallString = $_.UninstallString.Trim()
    if ($uninstallString -match '^"([^"]+)"\s*(.*)$') {
      $file      = $Matches[1]
      $extraArgs = $Matches[2].Trim()
    } elseif ($uninstallString -match '^(\S+\.exe)\s*(.*)$') {
      # Unquoted form - only well-defined when the path itself has no spaces.
      $file      = $Matches[1]
      $extraArgs = $Matches[2].Trim()
    } else {
      $file      = $uninstallString
      $extraArgs = ''
    }

    $packageArgs = @{
      packageName    = $packageName
      fileType       = 'exe'
      file           = $file
      # NSIS silent switch, plus whichever mode flag the registry recorded.
      silentArgs     = ("/S $extraArgs").Trim()
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

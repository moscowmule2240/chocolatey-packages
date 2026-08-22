$ErrorActionPreference = 'Stop'

# Shims created with Install-BinFile are not removed automatically.
Uninstall-BinFile -Name 'jadx'
Uninstall-BinFile -Name 'jadx-gui'

if (Test-ProcessAdminRights) {
    $specialFolder = [Environment+SpecialFolder]::CommonPrograms
} else {
    $specialFolder = [Environment+SpecialFolder]::Programs
}
$linkPath = Join-Path ([Environment]::GetFolderPath($specialFolder)) 'JADX GUI.lnk'
if (Test-Path $linkPath) { Remove-Item -Path $linkPath -Force }

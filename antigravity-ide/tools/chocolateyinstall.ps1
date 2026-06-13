$ErrorActionPreference = 'Stop'

$packageArgs = @{
  packageName    = $env:ChocolateyPackageName
  fileType       = 'exe'
  # x64 only. Google also ships windows-arm64; add an ARM64 branch here if needed.
  url            = 'https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.0.4-6381998290370560/windows-x64/Antigravity%20IDE.exe'
  softwareName   = 'Antigravity IDE*'
  checksum       = 'c4a83fe97ca159d9e67f4908955526ab6eb03fc747cab4af1a8d05f803e3bc6d'
  checksumType   = 'sha256'
  # InnoSetup silent switches.
  silentArgs     = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
  validExitCodes = @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs

# The installer auto-launches the IDE even in silent mode; close it so an
# unattended `choco install` finishes cleanly. Best-effort, non-fatal.
$timeout = 60
$timer = [System.Diagnostics.Stopwatch]::StartNew()
while ($timer.Elapsed.TotalSeconds -lt $timeout) {
  if (Get-Process -Name 'Antigravity*' -ErrorAction SilentlyContinue) {
    Start-Sleep -Seconds 5
    Stop-Process -Name 'Antigravity*' -Force -ErrorAction SilentlyContinue
    break
  }
  Start-Sleep -Seconds 1
}

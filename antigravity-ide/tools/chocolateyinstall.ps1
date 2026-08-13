$ErrorActionPreference = 'Stop'

# Per-architecture installers. Kept in sync by ../update.ps1 (AU).
$url64         = 'https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.4-6665745933926400/windows-x64/Antigravity%20IDE.exe'
$checksum64    = 'b5610a141242d684ff193866f99494666ec6453ce726a19aac385be1371a1c92'
$urlArm64      = 'https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.4-6665745933926400/windows-arm64/Antigravity%20IDE.exe'
$checksumArm64 = '16c0227e3ad492937d049817a6484fa76e02c9c6af856abbd4936a4cd272acc0'

# Detect ARM64 even when Chocolatey runs as an x64 (emulated) process on ARM hardware.
$isArm64 = ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') -or ($env:PROCESSOR_ARCHITEW6432 -eq 'ARM64')

$packageArgs = @{
  packageName    = $env:ChocolateyPackageName
  fileType       = 'exe'
  url            = if ($isArm64) { $urlArm64 }      else { $url64 }
  checksum       = if ($isArm64) { $checksumArm64 } else { $checksum64 }
  checksumType   = 'sha256'
  softwareName   = 'Antigravity IDE*'
  # InnoSetup silent switches.
  silentArgs     = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
  validExitCodes = @(0, 3010, 1641)
}

# The Antigravity installer launches the IDE when it finishes - even in silent
# mode - and in headless/unattended environments (e.g. the Chocolatey package
# test VM) the install process does NOT return until that IDE window is closed,
# so a plain silent install hangs until Chocolatey's timeout. Run a background
# watchdog that keeps closing the auto-launched IDE *while* the installer runs,
# so the install completes unattended. It spares the installer .exe itself
# (which runs from under Temp\chocolatey); only the launched app is closed.
$killer = Start-Job -ScriptBlock {
  while ($true) {
    Get-Process -Name 'Antigravity*' -ErrorAction SilentlyContinue |
      Where-Object { $_.Path -and $_.Path -notlike '*\Temp\chocolatey\*' } |
      Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
  }
}

try {
  Install-ChocolateyPackage @packageArgs
}
finally {
  Stop-Job   $killer -ErrorAction SilentlyContinue
  Remove-Job $killer -Force -ErrorAction SilentlyContinue
  # Final sweep in case the IDE was (re)launched right as the installer exited.
  # Wrapped so a transient access error here never masks the real install result.
  try {
    Get-Process -Name 'Antigravity*' -ErrorAction SilentlyContinue |
      Where-Object { $_.Path -and $_.Path -notlike '*\Temp\chocolatey\*' } |
      Stop-Process -Force -ErrorAction SilentlyContinue
  } catch { }
}

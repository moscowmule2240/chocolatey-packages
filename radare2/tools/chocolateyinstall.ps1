$ErrorActionPreference = 'Stop'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Rewritten by ../update.ps1 on every release. The checksums come from the GitHub
# release assets' digest field, so they are the hashes GitHub itself records.
$url32         = 'https://github.com/radareorg/radare2/releases/download/6.2.0/radare2-6.2.0-w32.zip'
$checksum32    = 'b06959f8221db6154e4d79051300585c86e9560942219b9e19d53a5114937b44'
$url64         = 'https://github.com/radareorg/radare2/releases/download/6.2.0/radare2-6.2.0-w64.zip'
$checksum64    = 'adb1ffd158066ea41316fa33b6d23b362aa9258df800721f7d15a42eefdd9202'
$urlArm64      = 'https://github.com/radareorg/radare2/releases/download/6.2.0/radare2-6.2.0-w64-arm64.zip'
$checksumArm64 = 'a5a956b8d9c3e0ff0290584215dcb85bc973866ade5d8247b9df9723c1fdebcf'

# Upstream ships three Windows archives. Install-ChocolateyZipPackage takes a
# 32-bit and a 64-bit url, which cannot express the third, so the archive is
# chosen here and handed over as a single pair.
#
# --x86 is honoured first: a helper given both urls would apply it for us, but a
# script that picks the url itself has to check chocolateyForceX86 itself.
# arm64 is tested before x64 because Windows on ARM also reports
# Is64BitOperatingSystem = $true.
$isArm64 = ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') -or ($env:PROCESSOR_ARCHITEW6432 -eq 'ARM64')

if ($env:chocolateyForceX86) {
    $url = $url32;    $checksum = $checksum32
} elseif ($isArm64) {
    $url = $urlArm64; $checksum = $checksumArm64
} elseif ([Environment]::Is64BitOperatingSystem) {
    $url = $url64;    $checksum = $checksum64
} else {
    $url = $url32;    $checksum = $checksum32
}

Install-ChocolateyZipPackage `
    -PackageName   $env:ChocolateyPackageName `
    -Url           $url `
    -Checksum      $checksum `
    -ChecksumType  'sha256' `
    -UnzipLocation $toolsDir

# The archive expands to radare2-<version>-<arch>/, a name that changes with every
# release and differs per architecture, so bin/ is located rather than rebuilt.
$binPath = Get-ChildItem -Path $toolsDir -Directory -Recurse -Filter 'bin' |
           Where-Object { Test-Path (Join-Path $_.FullName 'radare2.exe') } |
           Select-Object -First 1 -ExpandProperty FullName
if (-not $binPath) { throw "Could not find bin\radare2.exe under $toolsDir after unpacking." }

# Chocolatey shims every .exe in the package folder by itself, which covers all
# sixteen tools in bin/. Only the r2 alias needs registering: no executable
# carries that name, and the package being taken over provides it, so anyone
# upgrading would lose the command they actually type.
Install-BinFile -Name 'r2' -Path (Join-Path $binPath 'radare2.exe')

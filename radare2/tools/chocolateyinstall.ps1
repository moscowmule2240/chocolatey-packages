$ErrorActionPreference = 'Stop'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Rewritten by ../update.ps1 on every release. The checksums come from the GitHub
# release assets' digest field, so they are the hashes GitHub itself records.
$url32         = 'https://github.com/radareorg/radare2/releases/download/6.2.2/radare2-6.2.2-w32.zip'
$checksum32    = '7a1ff261f62ccdf7d313e77add4b9980f6429ac9682ae354a6eec7c41648e9be'
$url64         = 'https://github.com/radareorg/radare2/releases/download/6.2.2/radare2-6.2.2-w64.zip'
$checksum64    = '913e7d95e7458226a5e783240877f2c1d405398ab38ba176ce9b12e046e31f34'
$urlArm64      = 'https://github.com/radareorg/radare2/releases/download/6.2.2/radare2-6.2.2-w64-arm64.zip'
$checksumArm64 = '80800fa65310f34d1066841b6b84135470007776b5ef16e8849d331d9f3092f3'

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
# carries that name, and it is the command users actually type.
Install-BinFile -Name 'r2' -Path (Join-Path $binPath 'radare2.exe')

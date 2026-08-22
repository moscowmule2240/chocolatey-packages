$ErrorActionPreference = 'Stop'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Rewritten by ../update.ps1 on every release; the checksum comes from the
# GitHub release asset's digest field, so it is the hash GitHub itself records.
$url64      = 'https://github.com/skylot/jadx/releases/download/v1.5.6/jadx-1.5.6.zip'
$checksum64 = '545ea2be9c242511bc145755cf4bda2485ade42966e096f8b4d3da2a230e8974'

# The archive is Java bytecode and architecture-independent: one artifact serves
# both x64 and arm64, so only the 64-bit parameters are set.
Install-ChocolateyZipPackage `
    -PackageName    $env:ChocolateyPackageName `
    -Url64bit       $url64 `
    -Checksum64     $checksum64 `
    -ChecksumType64 'sha256' `
    -UnzipLocation  $toolsDir

# The archive unpacks to jadx-<version>/, so locate bin/ rather than assuming it.
$binPath = Get-ChildItem -Path $toolsDir -Directory -Recurse -Filter 'bin' |
           Where-Object { Test-Path (Join-Path $_.FullName 'jadx.bat') } |
           Select-Object -First 1 -ExpandProperty FullName
if (-not $binPath) { throw "Could not find bin\jadx.bat under $toolsDir after unpacking." }

$jadx    = Join-Path $binPath 'jadx.bat'
$jadxGui = Join-Path $binPath 'jadx-gui.bat'

Install-BinFile -Name 'jadx'     -Path $jadx
Install-BinFile -Name 'jadx-gui' -Path $jadxGui

if (Test-ProcessAdminRights) {
    $specialFolder = [Environment+SpecialFolder]::CommonPrograms
} else {
    $specialFolder = [Environment+SpecialFolder]::Programs
}
$linkPath = Join-Path ([Environment]::GetFolderPath($specialFolder)) 'JADX GUI.lnk'
Install-ChocolateyShortcut -ShortcutFilePath $linkPath -TargetPath $jadxGui

# Java check. This warns and never throws: unpacking and shimming do not need
# Java, and failing here would make the package uninstallable on the Chocolatey
# verifier, which runs without a JDK. jadx itself reports a clear error when it
# is started without a suitable runtime.
$javaRequirement = 'jadx requires 64-bit Java 11 or later. Any distribution works - for example Temurin, Zulu, the Microsoft Build of OpenJDK, or Oracle Java.'
$java = Get-Command 'java.exe' -ErrorAction SilentlyContinue

if (-not $java) {
    Write-Warning "Java was not found on PATH. $javaRequirement"
} else {
    $versionOutput = & $java.Source -version 2>&1 | Out-String

    # 'java version "1.8.0_401"' for 8 and older, 'openjdk version "21.0.1"' for 9+.
    $m = [regex]::Match($versionOutput, 'version "(\d+)(?:\.(\d+))?')
    if ($m.Success) {
        $major = [int]$m.Groups[1].Value
        if ($major -eq 1 -and $m.Groups[2].Success) { $major = [int]$m.Groups[2].Value }

        if ($major -lt 11) {
            Write-Warning "Java $major was found on PATH. $javaRequirement"
        }
    } else {
        Write-Warning "Could not read the version from 'java -version'. $javaRequirement"
    }

    if ($versionOutput -notmatch '64-Bit') {
        Write-Warning "The Java on PATH does not report a 64-bit VM. $javaRequirement"
    }
}

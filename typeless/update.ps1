<#
  AU (Chocolatey Automatic Updater) script for the typeless package.

  Typeless ships its Windows desktop app with electron-builder, which publishes an
  auto-update feed next to the installers - one per architecture:

    .../desktop-release/latest.yml   -> windows-x64
    .../desktop-release/arm64.yml    -> windows-arm64

  Each feed carries the version, the exact artifact filename and its sha512, so both
  are read instead of scraping the marketing site (whose download buttons only call
  /desktop/<platform>/download, a redirect resolved client-side).

  Taking the filename and hash straight from the feed means no artifact name is
  guessed, and there is no need to download ~270 MB of installers just to re-hash
  them - these are the same hashes the app's own updater verifies against.

  Keeps BOTH the windows-x64 and windows-arm64 url/checksum in sync (the package
  picks the right one at install time), plus the nuspec <version>.

  Local use:
    Install-Module AU -Scope CurrentUser   # (or: Install-Module Chocolatey-AU)
    ./update.ps1

  In CI this is invoked from the repo root by
  .github/workflows/update-typeless.yml.
#>
Import-Module AU
Import-Module (Join-Path $PSScriptRoot '../scripts/ChocoUpdate.psm1') -Force

$ErrorActionPreference = 'Stop'

# AU resolves the .nuspec relative to the current directory.
Set-Location -Path $PSScriptRoot

$ReleaseBase = 'https://typeless-static.com/desktop-release'

<#
  Reads one electron-builder feed and returns @{ Version; File; Checksum }.

  The feed repeats the artifact's hash: once nested under files: and once at the
  top level. The patterns below anchor to column 0 so they only ever pick up the
  top-level (canonical) entries, e.g.

    version: 2.9.0
    files:
      - url: Typeless-2.9.0-x64-Setup.exe
        sha512: 5gEl3nOdgUKH...
    path: Typeless-2.9.0-x64-Setup.exe
    sha512: 5gEl3nOdgUKH...

  The sha512 value is written on one line (2.9.0 onwards) or as a folded scalar,
  "sha512: >-" with the digest on the next line (up to 2.8.x). Both are accepted.

  The feeds are served with a non-text content type (see README.md, "upstream
  quirks"); Get-ValidatedContent decodes the body as UTF-8 before the validator
  sees it.
#>
function global:Get-ReleaseFeed {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Arch
    )

    return Get-ValidatedContent -Uri "$ReleaseBase/$Name" -What "the $Arch release info in $Name" -Validate {
        param($yml)
        # [ \t] rather than \s: \s would cross the line break when a value is empty.
        $version = [regex]::Match($yml, '(?m)^version:[ \t]*(\d+\.\d+\.\d+)[ \t]*\r?$')
        $file    = [regex]::Match($yml, '(?m)^path:[ \t]*(\S+)[ \t]*\r?$')
        # Inline or folded ("sha512: >-", digest on the next line). Only base64
        # characters are captured, so the ">-" marker is never taken as the digest.
        $sha     = [regex]::Match($yml, '(?m)^sha512:[ \t]*(?:>-[ \t]*\r?\n[ \t]*)?([A-Za-z0-9+/]+={0,2})[ \t]*\r?$')
        if (-not ($version.Success -and $file.Success -and $sha.Success)) { return $null }

        # The feed publishes sha512 base64-encoded; Chocolatey wants it as hex.
        # Invalid base64 or anything but 64 bytes is not a SHA-512 (a truncated or
        # wrapped digest); treat it as not found so the feed is fetched again and,
        # if it stays that way, the run fails.
        try { $bytes = [System.Convert]::FromBase64String($sha.Groups[1].Value) } catch { return $null }
        if ($bytes.Length -ne 64) { return $null }
        @{
            Version  = $version.Groups[1].Value
            File     = $file.Groups[1].Value
            Checksum = [System.BitConverter]::ToString($bytes).Replace('-', '').ToLowerInvariant()
        }
    }
}

function global:au_GetLatest {
    $x64 = Get-ReleaseFeed -Name 'latest.yml' -Arch 'windows-x64'
    $arm = Get-ReleaseFeed -Name 'arm64.yml'  -Arch 'windows-arm64'

    # A release is published one architecture at a time. If the two feeds disagree
    # the run caught it mid-publish - skip this run rather than shipping a package whose
    # two architectures are different versions.
    if ($x64.Version -ne $arm.Version) {
        throw "Architecture feeds disagree: latest.yml is $($x64.Version) but arm64.yml is $($arm.Version). Likely a partially-published release; will retry on the next run."
    }

    return @{
        Version       = $x64.Version
        URL64         = "$ReleaseBase/$($x64.File)"
        Checksum64    = $x64.Checksum
        URLArm64      = "$ReleaseBase/$($arm.File)"
        ChecksumArm64 = $arm.Checksum
    }
}

function global:au_SearchReplace {
    Get-DualArchSearchReplace -Latest $Latest
}

# Checksums come from the upstream feed (see au_GetLatest), so disable AU's own
# checksum step - it would re-download both installers to recompute them.
# -NoReadme: AU otherwise overwrites the nuspec <description> with the package
# folder's README.md (minus its first 2 lines). The nuspec carries a hand-curated,
# user-facing <description>, so opt out of that behaviour.
Update-Package -ChecksumFor none -NoReadme

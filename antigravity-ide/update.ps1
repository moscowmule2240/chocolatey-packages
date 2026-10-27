<#
  AU (Chocolatey Automatic Updater) script for the antigravity-ide package.

  Detects the latest Antigravity IDE version from the IDE's own update service,
  the endpoint the installed IDE polls for updates. It answers with JSON that
  names the per-arch installer URL, so a plain web request reads it - no
  ScraperAPI / paid API key needed.

  Keeps BOTH the windows-x64 and windows-arm64 url/checksum in sync (the package
  picks the right one at install time), plus the nuspec <version>.

  Local use:
    Install-Module AU -Scope CurrentUser   # (or: Install-Module Chocolatey-AU)
    ./update.ps1

  In CI this is invoked from the repo root by
  .github/workflows/update-antigravity-ide.yml.
#>
Import-Module AU
Import-Module (Join-Path $PSScriptRoot '../scripts/ChocoUpdate.psm1') -Force

$ErrorActionPreference = 'Stop'

# AU resolves the .nuspec relative to the current directory.
Set-Location -Path $PSScriptRoot

$UpdateService = 'https://antigravity-ide-auto-updater-974169037036.us-central1.run.app/api/update'
$Stable        = 'https://edgedl\.me\.gvt1\.com/edgedl/release2/j0qc3/antigravity/stable'

# Asks the update service for the latest stable installer of one architecture
# and returns its version, build number, URL and SHA-256.
function Get-LatestInstaller([string] $Platform, [string] $Arch) {
    Get-ValidatedContent -Uri "$UpdateService/$Platform/stable/latest" -What "the $Arch installer URL and SHA-256" -Validate {
        param($body)
        try { $answer = $body | ConvertFrom-Json } catch { return $null }
        $url    = [string]$answer.url
        $sha256 = [string]$answer.sha256hash
        # The $Stable anchor rejects any URL outside the edgedl
        # .../antigravity/stable/ path the package installs from. The service
        # spells the file name with a literal space; the package stores the URL
        # percent-encoded, the form tools\chocolateyinstall.ps1 keeps it in.
        # [0-9] rather than \d, which also matches non-ASCII digits.
        $m = [regex]::Match($url, "^$Stable/([0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)/$Arch/Antigravity(?: |%20)IDE\.exe\z")
        if (-not $m.Success) { return $null }
        if ($sha256 -notmatch '\A[0-9a-fA-F]{64}\z') { return $null }
        @{
            Version = $m.Groups[1].Value
            Build   = $m.Groups[2].Value
            URL     = $m.Value -replace ' ', '%20'
            Sha256  = $sha256.ToLowerInvariant()
        }
    }
}

function global:au_GetLatest {
    # The download page at https://antigravity.google/download is not used: its
    # download links have lagged its own version label (2.5.5 links under a
    # 2.6.0 label), while the update service already served 2.6.0.
    #
    # "-user" is the per-user installer; the system-wide platforms (win32-x64,
    # win32-arm64) answer HTTP 400 with an empty body. The last path segment is
    # normally the installed build's commit hash; "latest" matches no build, so
    # the service answers with the current release.
    $x64 = Get-LatestInstaller -Platform 'win32-x64-user'   -Arch 'windows-x64'
    $arm = Get-LatestInstaller -Platform 'win32-arm64-user' -Arch 'windows-arm64'

    # The two answers come from separate requests. During a release rollout
    # they can name different builds; one package must not mix them, so fail
    # and let the next scheduled run try again.
    if ($x64.Version -ne $arm.Version -or $x64.Build -ne $arm.Build) {
        throw "The update service named different builds: windows-x64 $($x64.Version)-$($x64.Build), windows-arm64 $($arm.Version)-$($arm.Build)"
    }

    return @{
        Version            = $x64.Version
        URL64              = $x64.URL
        URLArm64           = $arm.URL
        ServiceSha256      = $x64.Sha256
        ServiceSha256Arm64 = $arm.Sha256
    }
}

function global:au_BeforeUpdate {
    # Runs only when a newer version is found, so the ~200 MB installers are
    # downloaded for hashing only on a real update (not on every no-op run).
    $Latest.Checksum64    = Get-RemoteChecksum $Latest.URL64
    $Latest.ChecksumArm64 = Get-RemoteChecksum $Latest.URLArm64

    # The installed IDE verifies its installer against the service's sha256hash,
    # so the package does the same: a download that hashes differently is not
    # the installer the release names, and must not be packaged.
    if ($Latest.Checksum64 -ne $Latest.ServiceSha256) {
        throw "windows-x64 installer hashes to $($Latest.Checksum64), the update service names $($Latest.ServiceSha256)"
    }
    if ($Latest.ChecksumArm64 -ne $Latest.ServiceSha256Arm64) {
        throw "windows-arm64 installer hashes to $($Latest.ChecksumArm64), the update service names $($Latest.ServiceSha256Arm64)"
    }
}

function global:au_SearchReplace {
    Get-DualArchSearchReplace -Latest $Latest
}

# Checksums are computed in au_BeforeUpdate, so disable AU's own checksum step.
# -NoReadme: AU otherwise overwrites the nuspec <description> with the package
# folder's README.md (minus its first 2 lines). This package keeps a hand-curated,
# user-facing <description> in the nuspec, so opt out of that behaviour.
Update-Package -ChecksumFor none -NoReadme

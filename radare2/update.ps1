<#
  AU (Chocolatey Automatic Updater) script for the radare2 package.

  radare2 publishes GitHub releases, so the version, the three per-architecture
  archive URLs and their checksums all come from the releases API. Each asset
  carries a digest field ("sha256:<hex>"), so no archive is downloaded to be
  hashed - 36 MB saved on every release across the three of them.

  The package being taken over had no updater for stable releases at all: its
  only automation pulled AppVeyor artifacts to publish -git snapshots, and the
  stable versions were published by hand until they stopped.

  Local use:
    Install-Module AU -Scope CurrentUser   # (or: Install-Module Chocolatey-AU)
    ./update.ps1

  In CI this is invoked from the repo root by .github/workflows/update-radare2.yml.
#>
Import-Module AU
Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'ChocoUpdate.psm1')   -Force
Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'GitHubRelease.psm1') -Force

$ErrorActionPreference = 'Stop'

# AU resolves the .nuspec relative to the current directory.
Set-Location -Path $PSScriptRoot

$Repo = 'radareorg/radare2'

function global:au_GetLatest {
    $release = Get-GitHubLatestRelease -Repo $Repo
    $version = Get-ReleaseVersion -Release $release

    # Exact names only. The same release ships r2blob, wasi, ios-sdk and
    # android-sdk archives, and a loose match would happily pick one of those.
    # Select-ReleaseAsset throws on anything other than exactly one match.
    $w32   = Select-ReleaseAsset -Release $release -Name "radare2-$version-w32.zip"
    $w64   = Select-ReleaseAsset -Release $release -Name "radare2-$version-w64.zip"
    $arm64 = Select-ReleaseAsset -Release $release -Name "radare2-$version-w64-arm64.zip"

    return @{
        Version       = $version
        URL32         = $w32.browser_download_url
        Checksum32    = Get-AssetChecksum -Asset $w32     # $null if the digest is gone
        URL64         = $w64.browser_download_url
        Checksum64    = Get-AssetChecksum -Asset $w64
        URLArm64      = $arm64.browser_download_url
        ChecksumArm64 = Get-AssetChecksum -Asset $arm64
    }
}

function global:au_BeforeUpdate {
    # Only reached on a real update. The checksums are normally already set from
    # the asset digests; this is the fallback for a release that publishes none,
    # and it is the only path that downloads the archives.
    foreach ($pair in @(
        @{ Url = 'URL32';    Checksum = 'Checksum32'    },
        @{ Url = 'URL64';    Checksum = 'Checksum64'    },
        @{ Url = 'URLArm64'; Checksum = 'ChecksumArm64' }
    )) {
        if (-not $Latest[$pair.Checksum]) {
            Write-Host "  $($pair.Url) asset carries no digest; hashing the download instead."
            $Latest[$pair.Checksum] = Get-RemoteChecksum $Latest[$pair.Url]
        }
    }
}

function global:au_SearchReplace {
    @{
        'tools\chocolateyinstall.ps1' = @{
            "(?i)(\`$url32\s*=\s*)'[^']*'"         = "`${1}'$($Latest.URL32)'"
            "(?i)(\`$checksum32\s*=\s*)'[^']*'"    = "`${1}'$($Latest.Checksum32)'"
            "(?i)(\`$url64\s*=\s*)'[^']*'"         = "`${1}'$($Latest.URL64)'"
            "(?i)(\`$checksum64\s*=\s*)'[^']*'"    = "`${1}'$($Latest.Checksum64)'"
            "(?i)(\`$urlArm64\s*=\s*)'[^']*'"      = "`${1}'$($Latest.URLArm64)'"
            "(?i)(\`$checksumArm64\s*=\s*)'[^']*'" = "`${1}'$($Latest.ChecksumArm64)'"
        }
    }
}

# Checksums come from the release assets (see au_GetLatest), so disable AU's own
# checksum step - it would re-download the archives to recompute them.
# -NoReadme: AU otherwise overwrites the nuspec <description> with the package
# folder's README.md (minus its first 2 lines). We keep a hand-curated,
# user-facing <description> in the nuspec, so opt out of that behaviour.
Update-Package -ChecksumFor none -NoReadme

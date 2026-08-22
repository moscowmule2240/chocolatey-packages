<#
  AU (Chocolatey Automatic Updater) script for the jadx package.

  jadx publishes GitHub releases, so the version, the artifact URL and its
  checksum all come from the releases API. The asset carries a digest field
  ("sha256:<hex>"), which means we never download the ~69 MB archive just to
  hash it - the same property the typeless feed gives us. Get-RemoteChecksum is
  only used if that field ever disappears.

  The release archive is Java bytecode and architecture-independent, so there is
  a single url/checksum pair rather than the x64/arm64 pair the other two
  packages carry. That is why this script writes its own au_SearchReplace
  instead of calling Get-DualArchSearchReplace.

  Local use:
    Install-Module AU -Scope CurrentUser   # (or: Install-Module Chocolatey-AU)
    ./update.ps1

  In CI this is invoked from the repo root by .github/workflows/update-jadx.yml.
#>
Import-Module AU
Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'ChocoUpdate.psm1')   -Force
Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'GitHubRelease.psm1') -Force

$ErrorActionPreference = 'Stop'

# AU resolves the .nuspec relative to the current directory.
Set-Location -Path $PSScriptRoot

$Repo = 'skylot/jadx'

function global:au_GetLatest {
    $release = Get-GitHubLatestRelease -Repo $Repo
    $version = Get-ReleaseVersion -Release $release

    # Exact name only: the same release also ships jadx-gui-<version>-win.zip and
    # jadx-gui-<version>-with-jre-win.zip, and a loose match could pick one of
    # those. Select-ReleaseAsset throws on anything other than one match.
    $asset = Select-ReleaseAsset -Release $release -Name "jadx-$version.zip"

    return @{
        Version    = $version
        URL64      = $asset.browser_download_url
        Checksum64 = Get-AssetChecksum -Asset $asset   # $null if the digest is gone
    }
}

function global:au_BeforeUpdate {
    # Only reached on a real update. Normally the checksum is already set from the
    # asset digest; this is the fallback for a release that publishes no digest,
    # and it is the only path that downloads the archive.
    if (-not $Latest.Checksum64) {
        Write-Host '  Release asset carries no digest; hashing the download instead.'
        $Latest.Checksum64 = Get-RemoteChecksum $Latest.URL64
    }
}

function global:au_SearchReplace {
    @{
        'tools\chocolateyinstall.ps1' = @{
            "(?i)(\`$url64\s*=\s*)'[^']*'"      = "`${1}'$($Latest.URL64)'"
            "(?i)(\`$checksum64\s*=\s*)'[^']*'" = "`${1}'$($Latest.Checksum64)'"
        }
    }
}

# Checksums come from the release asset (see au_GetLatest), so disable AU's own
# checksum step - it would re-download the archive to recompute them.
# -NoReadme: AU otherwise overwrites the nuspec <description> with the package
# folder's README.md (minus its first 2 lines). We keep a hand-curated,
# user-facing <description> in the nuspec, so opt out of that behaviour.
Update-Package -ChecksumFor none -NoReadme

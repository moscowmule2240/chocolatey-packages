<#
  Turns a GitHub repository's latest release into the pieces an AU script needs:
  a version, an asset, and a checksum.

  Routes its HTTP through ChocoUpdate's Get-ValidatedContent so GitHub gets the
  same retry and diagnostic behaviour as the HTML scrapers.

  Note on visibility: a nested Import-Module binds into this module's scope, not
  the caller's. Scripts that need both modules import both explicitly.
#>

Import-Module (Join-Path $PSScriptRoot 'ChocoUpdate.psm1') -Force

<#
  Reads /repos/<owner>/<repo>/releases/latest, which GitHub already filters to
  exclude drafts and prereleases.

  Authenticates when GITHUB_TOKEN is present. The reason is less the ceiling
  (1,000 requests/hour/repository for the Actions token) than that the
  unauthenticated 60/hour is metered per IP address, which shared CI runners
  exhaust.
#>
function Get-GitHubLatestRelease {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Repo)

    $headers = @{
        'User-Agent' = 'Mozilla/5.0'
        'Accept'     = 'application/vnd.github+json'
    }
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }

    return Get-ValidatedContent -Uri "https://api.github.com/repos/$Repo/releases/latest" `
        -Headers $headers -What "the latest release of $Repo" -Validate {
            param($body)
            try { $release = $body | ConvertFrom-Json } catch { return $null }
            if (-not $release.tag_name) { return $null }
            if (-not $release.assets)   { return $null }
            return $release
        }
}

<#
  Reads the x.y[.z] version out of a release tag, tolerating a leading 'v'.
  Throws rather than guessing: a wrong version here would be published.
#>
function Get-ReleaseVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Release)

    $tag = [string]$Release.tag_name
    $m   = [regex]::Match($tag, '^v?(\d+\.\d+(?:\.\d+)?)$')
    if (-not $m.Success) {
        throw "Cannot read a version from the release tag '$tag'."
    }
    return $m.Groups[1].Value
}

<#
  Returns the single asset with an exactly matching name. Zero matches means the
  upstream naming changed; more than one means the name is ambiguous. Either way
  guessing would ship the wrong artifact, so both throw.
#>
function Select-ReleaseAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]         $Release,
        [Parameter(Mandatory)][string] $Name
    )

    $found = @($Release.assets | Where-Object { $_.name -eq $Name })
    if ($found.Count -ne 1) {
        $available = (@($Release.assets | ForEach-Object { $_.name })) -join ', '
        throw "Expected exactly one asset named '$Name', found $($found.Count). Available: $available"
    }
    return $found[0]
}

<#
  Reads the asset's sha256 digest, which GitHub publishes as 'sha256:<hex>'.
  Returns $null when the field is absent so callers can fall back to hashing the
  download; throws when the field is present but in a form we do not understand,
  because silently ignoring it would hide a format change.
#>
function Get-AssetChecksum {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Asset)

    if (-not $Asset.digest) { return $null }

    $m = [regex]::Match([string]$Asset.digest, '^sha256:([0-9a-fA-F]{64})$')
    if (-not $m.Success) {
        throw "Asset '$($Asset.name)' has a digest this script cannot read: $($Asset.digest)"
    }
    return $m.Groups[1].Value.ToLowerInvariant()
}

Export-ModuleMember -Function Get-GitHubLatestRelease, Get-ReleaseVersion, Select-ReleaseAsset, Get-AssetChecksum

<#
  AU (Chocolatey Automatic Updater) script for the typeless package.

  Typeless ships its Windows desktop app with electron-builder, which publishes an
  auto-update feed next to the installers - one per architecture:

    .../desktop-release/latest.yml   -> windows-x64
    .../desktop-release/arm64.yml    -> windows-arm64

  Each feed carries the version, the exact artifact filename and its sha512, so we
  read both instead of scraping the marketing site (whose download buttons only call
  /desktop/<platform>/download, a redirect resolved client-side).

  Taking the filename and hash straight from the feed means we never guess an
  artifact name, and never have to download ~270 MB of installers just to re-hash
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
$ErrorActionPreference = 'Stop'

# AU resolves the .nuspec relative to the current directory.
Set-Location -Path $PSScriptRoot

$ReleaseBase = 'https://typeless-static.com/desktop-release'
$Headers     = @{ 'User-Agent' = 'Mozilla/5.0' }

# Retry transient/incomplete responses rather than failing the whole run on one
# bad fetch, with growing delays.
$RetryDelaysSeconds = @(5, 15, 30)

<#
  Fetches $Uri and hands the body to $Validate, which returns the extracted
  value on success or $null when the body does not contain what we need.

  A $null verdict is treated exactly like a failed request: both are retried,
  because a CDN can answer 200 with a body that is empty or truncated. Retries
  append a cache-buster and ask for a revalidated copy, so we do not just re-read
  the same bad cached response. Note that Invoke-WebRequest -MaximumRetryCount
  would not help: it only retries on HTTP error status codes.
#>
function global:Get-ValidatedContent {
    param(
        [Parameter(Mandatory)][string]      $Uri,
        [Parameter(Mandatory)][scriptblock] $Validate,
        [Parameter(Mandatory)][string]      $What
    )

    $attempts    = $RetryDelaysSeconds.Count + 1
    $lastProblem = 'no attempt was made'

    for ($i = 0; $i -lt $attempts; $i++) {
        if ($i -gt 0) {
            $delay = $RetryDelaysSeconds[$i - 1]
            Write-Host "  $What not found ($lastProblem); retrying in ${delay}s [$($i + 1)/$attempts]"
            Start-Sleep -Seconds $delay
        }

        $requestUri     = $Uri
        $requestHeaders = $Headers
        if ($i -gt 0) {
            $separator      = if ($Uri.Contains('?')) { '&' } else { '?' }
            $requestUri     = "$Uri$separator" + 'cb=' + [guid]::NewGuid().ToString('N')
            $requestHeaders = $Headers + @{ 'Cache-Control' = 'no-cache'; 'Pragma' = 'no-cache' }
        }

        try {
            $response = Invoke-WebRequest -Uri $requestUri -Headers $requestHeaders -UseBasicParsing
        } catch {
            $lastProblem = "request failed: $($_.Exception.Message)"
            continue
        }

        # Invoke-WebRequest only hands back a [string] Content for text-ish content
        # types; anything else arrives as [byte[]]. These feeds are served as
        # application/x-www-form-urlencoded, so they take the byte[] path - and
        # [string]-casting a byte[] yields "112 100 100 ..." (the decimal values
        # joined by spaces), not the document. Decode explicitly instead.
        $raw     = $response.Content
        $content = if ($raw -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($raw) } else { [string]$raw }

        $result = & $Validate $content
        if ($result) { return $result }

        $tail = if ($content.Length -gt 200) { $content.Substring($content.Length - 200) } else { $content }
        $lastProblem = "HTTP $([int]$response.StatusCode), $($content.Length) bytes, ends with: $tail"
    }

    throw "Could not find $What at $Uri after $attempts attempts. Last response: $lastProblem"
}

<#
  Reads one electron-builder feed and returns @{ Version; File; Checksum }.

  The feed repeats the artifact's hash: once nested under files: and once at the
  top level. The patterns below anchor to column 0 so they only ever pick up the
  top-level (canonical) entries, e.g.

    version: 2.1.0
    files:
      - url: Typeless-2.1.0-x64-Setup.exe
        sha512: >-
          DVyT5Ti0kPNa...
    path: Typeless-2.1.0-x64-Setup.exe
    sha512: >-
      DVyT5Ti0kPNa...
#>
function global:Get-ReleaseFeed {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Arch
    )

    return Get-ValidatedContent -Uri "$ReleaseBase/$Name" -What "the $Arch release info in $Name" -Validate {
        param($yml)
        $version = [regex]::Match($yml, '(?m)^version:\s*(\d+\.\d+\.\d+)\s*$')
        $file    = [regex]::Match($yml, '(?m)^path:\s*(\S+)\s*$')
        # Folded scalar: the base64 digest sits on the line after "sha512: >-".
        $sha     = [regex]::Match($yml, '(?m)^sha512:\s*>-\s*\r?\n\s*(\S+)\s*$')
        if (-not ($version.Success -and $file.Success -and $sha.Success)) { return $null }

        # The feed publishes sha512 base64-encoded; Chocolatey wants it as hex.
        $bytes = [System.Convert]::FromBase64String($sha.Groups[1].Value)
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
    # we caught it mid-publish - skip this run rather than shipping a package whose
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
    @{
        'tools\chocolateyinstall.ps1' = @{
            "(?i)(\`$url64\s*=\s*)'[^']*'"         = "`${1}'$($Latest.URL64)'"
            "(?i)(\`$checksum64\s*=\s*)'[^']*'"    = "`${1}'$($Latest.Checksum64)'"
            "(?i)(\`$urlArm64\s*=\s*)'[^']*'"      = "`${1}'$($Latest.URLArm64)'"
            "(?i)(\`$checksumArm64\s*=\s*)'[^']*'" = "`${1}'$($Latest.ChecksumArm64)'"
        }
    }
}

# Checksums come from the upstream feed (see au_GetLatest), so disable AU's own
# checksum step - it would re-download both installers to recompute them.
# -NoReadme: AU otherwise overwrites the nuspec <description> with the package
# folder's README.md (minus its first 2 lines). We keep a hand-curated,
# user-facing <description> in the nuspec, so opt out of that behaviour.
Update-Package -ChecksumFor none -NoReadme

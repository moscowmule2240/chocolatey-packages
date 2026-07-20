<#
  AU (Chocolatey Automatic Updater) script for the antigravity-ide package.

  Detects the latest Antigravity IDE version directly from the official download
  page. The real per-arch installer URLs are embedded as plain string literals
  in that page's HTML, so we can read them with a plain web request - no
  ScraperAPI / paid API key needed.

  (Until ~2026-07-20 the page was a JavaScript SPA that hid the URLs inside a
  content-hashed main-*.js bundle, requiring a two-step scrape. The site was
  rebuilt on Astro and now ships the URLs in the download page itself.)

  Keeps BOTH the windows-x64 and windows-arm64 url/checksum in sync (the package
  picks the right one at install time), plus the nuspec <version>.

  Local use:
    Install-Module AU -Scope CurrentUser   # (or: Install-Module Chocolatey-AU)
    ./update.ps1

  In CI this is invoked from the repo root by
  .github/workflows/update-antigravity-ide.yml.
#>
Import-Module AU
$ErrorActionPreference = 'Stop'

# AU resolves the .nuspec relative to the current directory.
Set-Location -Path $PSScriptRoot

$DownloadPage = 'https://antigravity.google/download'
$Headers      = @{ 'User-Agent' = 'Mozilla/5.0' }
$Stable       = 'https://edgedl\.me\.gvt1\.com/edgedl/release2/j0qc3/antigravity/stable'

# antigravity.google is served through Google Frontend with a 10-minute shared
# edge cache, and it occasionally answers 200 with a body that is missing the
# markup we scrape (observed ~3% of CI runs). Retry those, with growing delays.
$RetryDelaysSeconds = @(5, 15, 30)

<#
  Fetches $Uri and hands the body to $Validate, which returns the extracted
  value on success or $null when the body does not contain what we need.

  A $null verdict is treated exactly like a failed request: both are retried,
  because the failure we are guarding against is a *successful* response whose
  body is short. Retries append a cache-buster and ask the edge to revalidate,
  so we do not just re-read the same bad cached copy. Note that
  Invoke-WebRequest -MaximumRetryCount would not help here: it only retries on
  HTTP error status codes.
#>
function global:Get-ValidatedContent {
    param(
        [Parameter(Mandatory)][string]      $Uri,
        [Parameter(Mandatory)][scriptblock] $Validate,
        [Parameter(Mandatory)][string]      $What
    )

    $attempts = $RetryDelaysSeconds.Count + 1
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

        $content = [string]$response.Content
        $result  = & $Validate $content
        if ($result) { return $result }

        # Keep the tail: the markup we scrape sits at the very end of the
        # document, so a truncated body is the prime suspect and this is the
        # evidence that tells us so.
        $tail = if ($content.Length -gt 200) { $content.Substring($content.Length - 200) } else { $content }
        $lastProblem = "HTTP $([int]$response.StatusCode), $($content.Length) bytes, ends with: $tail"
    }

    throw "Could not find $What at $Uri after $attempts attempts. Last response: $lastProblem"
}

function global:au_GetLatest {
    # Both per-arch IDE installer URLs are plain string literals in the download
    # page's HTML, e.g.
    #   .../stable/2.1.1-6123990880747520/windows-x64/Antigravity%20IDE.exe
    # The $Stable anchor pins the match to the edgedl .../antigravity/stable/
    # path so we never pick up the unrelated antigravity-hub build that the same
    # page links from storage.googleapis.com.
    $urls = Get-ValidatedContent -Uri $DownloadPage -What 'the windows-x64/arm64 installer URLs' -Validate {
        param($html)
        $x64 = [regex]::Match($html, "$Stable/(\d+\.\d+\.\d+)-\d+/windows-x64/Antigravity%20IDE\.exe")
        $arm = [regex]::Match($html, "$Stable/\d+\.\d+\.\d+-\d+/windows-arm64/Antigravity%20IDE\.exe")
        if (-not ($x64.Success -and $arm.Success)) { return $null }
        @{
            Version  = $x64.Groups[1].Value
            URL64    = $x64.Value
            URLArm64 = $arm.Value
        }
    }

    return $urls
}

function global:au_BeforeUpdate {
    # Runs only when a newer version is found, so the ~230 MB installers are
    # downloaded for hashing only on a real update (not on every no-op run).
    $Latest.Checksum64    = Get-RemoteChecksum $Latest.URL64
    $Latest.ChecksumArm64 = Get-RemoteChecksum $Latest.URLArm64
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

# Checksums are computed in au_BeforeUpdate, so disable AU's own checksum step.
# -NoReadme: AU otherwise overwrites the nuspec <description> with the package
# folder's README.md (minus its first 2 lines). We keep a hand-curated,
# user-facing <description> in the nuspec, so opt out of that behaviour.
Update-Package -ChecksumFor none -NoReadme

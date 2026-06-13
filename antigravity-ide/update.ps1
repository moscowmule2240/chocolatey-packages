<#
  AU (Chocolatey Automatic Updater) script for the antigravity-ide package.

  Detects the latest Antigravity IDE version directly from the official download
  page. That page is a JavaScript SPA, but the real installer URLs are hard-coded
  as string literals inside its content-hashed main-*.js bundle, so we can read
  them with plain web requests - no ScraperAPI / paid API key needed (unlike
  scraping the JS-rendered page).

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

function global:au_GetLatest {
    # 1) The download page references a content-hashed main-*.js bundle.
    $html   = (Invoke-WebRequest -Uri $DownloadPage -Headers $Headers -UseBasicParsing).Content
    $bundle = [regex]::Match($html, 'main-[A-Za-z0-9]+\.js').Value
    if (-not $bundle) { throw "Could not find the main-*.js bundle on $DownloadPage" }

    # 2) The Windows x64 IDE installer URL is a literal inside that bundle, e.g.
    #    .../antigravity/stable/2.0.4-6381998290370560/windows-x64/Antigravity%20IDE.exe
    $js = (Invoke-WebRequest -Uri "https://antigravity.google/$bundle" -Headers $Headers -UseBasicParsing).Content
    $rx = 'https://edgedl\.me\.gvt1\.com/edgedl/release2/j0qc3/antigravity/stable/(\d+\.\d+\.\d+)-\d+/windows-x64/Antigravity%20IDE\.exe'
    $m  = [regex]::Match($js, $rx)
    if (-not $m.Success) { throw "Could not find the Antigravity IDE windows-x64 URL in $bundle" }

    return @{
        Version = $m.Groups[1].Value
        URL64   = $m.Value
    }
}

function global:au_SearchReplace {
    @{
        'tools\chocolateyinstall.ps1' = @{
            "(?i)(\burl\s*=\s*)'[^']*'"      = "`${1}'$($Latest.URL64)'"
            "(?i)(\bchecksum\s*=\s*)'[^']*'" = "`${1}'$($Latest.Checksum64)'"
        }
    }
}

# -ChecksumFor 64: AU downloads URL64 and computes the sha256 before packing.
# If the detected Version equals the nuspec version, AU reports "no updates" and
# produces no .nupkg (so the workflow's test/push steps are skipped).
Update-Package -ChecksumFor 64

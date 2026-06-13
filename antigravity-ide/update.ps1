<#
  AU (Chocolatey Automatic Updater) script for the antigravity-ide package.

  Detects the latest Antigravity IDE version directly from the official download
  page. That page is a JavaScript SPA, but the real installer URLs are hard-coded
  as string literals inside its content-hashed main-*.js bundle, so we can read
  them with plain web requests - no ScraperAPI / paid API key needed.

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

function global:au_GetLatest {
    # 1) The download page references a content-hashed main-*.js bundle.
    $html   = (Invoke-WebRequest -Uri $DownloadPage -Headers $Headers -UseBasicParsing).Content
    $bundle = [regex]::Match($html, 'main-[A-Za-z0-9]+\.js').Value
    if (-not $bundle) { throw "Could not find the main-*.js bundle on $DownloadPage" }

    # 2) Both per-arch IDE installer URLs are string literals inside that bundle,
    #    e.g. .../stable/2.0.4-6381998290370560/windows-x64/Antigravity%20IDE.exe
    $js  = (Invoke-WebRequest -Uri "https://antigravity.google/$bundle" -Headers $Headers -UseBasicParsing).Content
    $x64 = [regex]::Match($js, "$Stable/(\d+\.\d+\.\d+)-\d+/windows-x64/Antigravity%20IDE\.exe")
    $arm = [regex]::Match($js, "$Stable/\d+\.\d+\.\d+-\d+/windows-arm64/Antigravity%20IDE\.exe")
    if (-not $x64.Success) { throw "Could not find the windows-x64 URL in $bundle" }
    if (-not $arm.Success) { throw "Could not find the windows-arm64 URL in $bundle" }

    return @{
        Version  = $x64.Groups[1].Value
        URL64    = $x64.Value
        URLArm64 = $arm.Value
    }
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
        # Keep VERIFICATION.txt accurate so it never lags the actual binaries.
        'tools\VERIFICATION.txt' = @{
            "(?i)(windows-x64 url:\s*).*"                  = "`${1}$($Latest.URL64)"
            "(?i)(windows-x64 checksum:\s*)[0-9a-f]{64}"   = "`${1}$($Latest.Checksum64)"
            "(?i)(windows-arm64 url:\s*).*"                = "`${1}$($Latest.URLArm64)"
            "(?i)(windows-arm64 checksum:\s*)[0-9a-f]{64}" = "`${1}$($Latest.ChecksumArm64)"
        }
    }
}

# Checksums are computed in au_BeforeUpdate, so disable AU's own checksum step.
Update-Package -ChecksumFor none

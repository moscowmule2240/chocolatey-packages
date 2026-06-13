<#
  Decides whether a freshly-built package version should be pushed to the
  Chocolatey community feed.

  Output (stdout): "PROCEED_WITH_PUSH" or "SKIP_PUSH"

  SKIP when the version page already exists on community.chocolatey.org (HTTP 200)
  or when we already recorded a successful push locally (logs/pushed-versions.log).

  Note: we check the package PAGE (not the OData feed) on purpose. A submission
  still in moderation is hidden from the feed but its /packages/<id>/<version>
  page already returns 200 - so the page is the reliable "is this taken?" signal.
#>
param(
    [Parameter(Mandatory)] [string] $PackageId,
    [Parameter(Mandatory)] [string] $PackageVersion
)

$ErrorActionPreference = 'SilentlyContinue'

$pageUrl = "https://community.chocolatey.org/packages/$PackageId/$PackageVersion"
$logDir  = Join-Path $PSScriptRoot '..' 'logs'
$logFile = Join-Path $logDir 'pushed-versions.log'

try {
    $resp = Invoke-WebRequest -Uri $pageUrl -UseBasicParsing -Method Get -TimeoutSec 20
    if ($resp.StatusCode -eq 200) {
        Write-Host "$PackageId/$PackageVersion already exists on Chocolatey.org."
        Write-Output 'SKIP_PUSH'; exit 0
    }
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code -eq 404) {
        Write-Host "$PackageId/$PackageVersion not found on Chocolatey.org (404)."
    } else {
        Write-Host "Status check inconclusive (HTTP $code). Falling back to local log."
    }
}

if (Test-Path $logFile) {
    if ((Get-Content $logFile -Raw) -match [regex]::Escape("$PackageId/$PackageVersion")) {
        Write-Host "$PackageId/$PackageVersion found in local push log."
        Write-Output 'SKIP_PUSH'; exit 0
    }
}

Write-Output 'PROCEED_WITH_PUSH'
exit 0

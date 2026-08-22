<#
  Shared helpers for the AU update scripts in this repository.

  Imported by each package's update.ps1. AU invokes au_GetLatest and friends in
  the global scope; Import-Module called from a script binds into global session
  state, so the exports below are visible from inside those functions. Do not
  import this with -Scope Local.
#>

$script:DefaultHeaders     = @{ 'User-Agent' = 'Mozilla/5.0' }
$script:RetryDelaysSeconds = @(5, 15, 30)

<#
  Fetches $Uri and hands the body to $Validate, which returns the extracted
  value on success or $null when the body does not contain what we need.

  A $null verdict is treated exactly like a failed request: both are retried,
  because a CDN can answer 200 with a body that is empty or truncated. Retries
  append a cache-buster and ask for a revalidated copy, so we do not just
  re-read the same bad cached response. Note that Invoke-WebRequest
  -MaximumRetryCount would not help: it only retries on HTTP error status codes.
#>
function Get-ValidatedContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]      $Uri,
        [Parameter(Mandatory)][scriptblock] $Validate,
        [Parameter(Mandatory)][string]      $What,
        [hashtable]                         $Headers
    )

    if (-not $Headers) { $Headers = $script:DefaultHeaders }

    $attempts    = $script:RetryDelaysSeconds.Count + 1
    $lastProblem = 'no attempt was made'

    for ($i = 0; $i -lt $attempts; $i++) {
        if ($i -gt 0) {
            $delay = $script:RetryDelaysSeconds[$i - 1]
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
        # types; anything else arrives as [byte[]]. The typeless feeds are served as
        # application/x-www-form-urlencoded, so they take the byte[] path - and
        # [string]-casting a byte[] yields "112 100 100 ..." (the decimal values
        # joined by spaces), not the document. Decode explicitly instead.
        $raw     = $response.Content
        $content = if ($raw -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($raw) } else { [string]$raw }

        $result = & $Validate $content
        if ($result) { return $result }

        # Keep the tail: the markup we scrape sits at the very end of the
        # document, so a truncated body is the prime suspect and this is the
        # evidence that tells us so.
        $tail = if ($content.Length -gt 200) { $content.Substring($content.Length - 200) } else { $content }
        $lastProblem = "HTTP $([int]$response.StatusCode), $($content.Length) bytes, ends with: $tail"
    }

    throw "Could not find $What at $Uri after $attempts attempts. Last response: $lastProblem"
}

<#
  Builds the au_SearchReplace table for packages that ship one x64 and one arm64
  artifact and store them in tools\chocolateyinstall.ps1 as four variables.

  $Latest is AU's $Latest - accepted untyped because AU may hand over either a
  hashtable or a PSCustomObject depending on how au_GetLatest built it.
#>
function Get-DualArchSearchReplace {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Latest)

    return @{
        'tools\chocolateyinstall.ps1' = @{
            "(?i)(\`$url64\s*=\s*)'[^']*'"         = "`${1}'$($Latest.URL64)'"
            "(?i)(\`$checksum64\s*=\s*)'[^']*'"    = "`${1}'$($Latest.Checksum64)'"
            "(?i)(\`$urlArm64\s*=\s*)'[^']*'"      = "`${1}'$($Latest.URLArm64)'"
            "(?i)(\`$checksumArm64\s*=\s*)'[^']*'" = "`${1}'$($Latest.ChecksumArm64)'"
        }
    }
}

Export-ModuleMember -Function Get-ValidatedContent, Get-DualArchSearchReplace

# Shared AU Update Modules and the jadx Package — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the duplicated transport code out of the two `update.ps1` scripts into shared PowerShell modules, add a GitHub Releases source adapter, and build the `jadx` package on top of it.

**Architecture:** Two script modules under `scripts/`. `ChocoUpdate.psm1` owns HTTP transport (the retrying, self-diagnosing fetch helper) and the dual-architecture `au_SearchReplace` shape. `GitHubRelease.psm1` is a source adapter that turns a GitHub repository into a version, an asset URL and a checksum. Each package's `update.ps1` keeps its own `au_*` functions and imports what it needs. Pester covers the pure logic; the existing CI install/uninstall step covers the rest.

**Tech Stack:** PowerShell 7 (`pwsh`) for update scripts and tests, Windows PowerShell 5.1 for Chocolatey install scripts, Pester 5, Chocolatey AU, GitHub Actions on `windows-latest`.

**Spec:** `docs/superpowers/specs/2026-08-22-au-shared-modules-design.md`

## Global Constraints

- **Two PowerShell dialects.** `update.ps1` and the modules run under `pwsh` 7 (CI sets `shell: pwsh`). `tools/chocolateyinstall.ps1` and `tools/chocolateyuninstall.ps1` are executed by Chocolatey under **Windows PowerShell 5.1** — they must not use pwsh-7-only syntax (no ternary `? :`, no `??`, no `-Parallel`), and they must not import the modules.
- **AU calls `au_*` in the global scope.** Keep the `global:` prefix on every `au_GetLatest`, `au_BeforeUpdate` and `au_SearchReplace`. Import modules with plain `Import-Module` from the script — never `-Scope Local`, which would hide the exports from those functions.
- **Always `Import-Module ... -Force`.** Without it a stale copy from an earlier run in the same session wins.
- **Retry policy is fixed:** 4 attempts, delays `@(5, 15, 30)` seconds, cache-buster plus `Cache-Control: no-cache` on retries.
- **The diagnostic throw is load-bearing.** On final failure the message must carry HTTP status, body length, and the trailing 200 characters. Two real bugs were found through it; do not trim it.
- **Checksum types:** `sha512` for typeless (from its feed), `sha256` for jadx (from the release asset digest), whatever `Get-RemoteChecksum` produces for antigravity-ide (`sha256` by default).
- **jadx publishes nothing until the maintainer handover completes** (response window ends 2026-08-29). Its workflow ships with `schedule:` commented out.
- **Icon URLs use jsdelivr**, not raw GitHub: `https://cdn.jsdelivr.net/gh/moscowmule2240/chocolatey-packages@main/<pkg>/icon.png` (CPMR0076).
- **Commit messages** follow the repository style: lowercase `<scope>: <imperative summary>`, English, no first person.

## File Structure

| File | Responsibility |
| --- | --- |
| `scripts/ChocoUpdate.psm1` | HTTP transport with retries and diagnostics; the dual-arch `au_SearchReplace` builder |
| `scripts/GitHubRelease.psm1` | GitHub Releases adapter: latest release, version from tag, asset selection, checksum from digest |
| `tests/ChocoUpdate.Tests.ps1` | Pester tests for the transport module |
| `tests/GitHubRelease.Tests.ps1` | Pester tests for the GitHub adapter |
| `antigravity-ide/update.ps1` | Keeps `au_GetLatest` (HTML scrape); drops the inlined helper |
| `typeless/update.ps1` | Keeps `au_GetLatest` and `Get-ReleaseFeed`; drops the inlined helper |
| `jadx/jadx.nuspec` | Package metadata, no `<dependencies>` |
| `jadx/tools/chocolateyinstall.ps1` | Downloads and unpacks the zip, shims both bats, warns about Java |
| `jadx/tools/chocolateyuninstall.ps1` | Removes both shims and the shortcut |
| `jadx/update.ps1` | AU script driving `GitHubRelease.psm1` |
| `jadx/README.md`, `jadx/icon.png` | Package notes and icon, following the existing two packages |
| `.github/workflows/update-jadx.yml` | Same shape as the other two, `schedule:` commented out |
| `.github/workflows/test.yml` | Runs Pester on push and pull request |

## Deviations from the spec

Three, all deliberate.

**1. Transitive module imports do not work the way the spec assumes.** The spec says a package using GitHub "imports only `GitHubRelease.psm1` and receives the transport module transitively". That is not how PowerShell script modules behave: `Import-Module` inside a `.psm1` binds into that module's own scope, and the nested module's functions are not re-exported to the caller unless declared in a manifest. Task 2 Step 5 verifies this empirically. Either way Task 6 imports both modules explicitly, which is correct under both behaviours.

**2. Pester tests are added; the spec does not mention tests.** The spec's Verification section relies entirely on running the update scripts against live upstreams. That catches integration failures but not logic regressions, and consolidating 51 duplicated lines into one copy concentrates the blast radius: a defect in `Get-ValidatedContent` now breaks three packages instead of one. The pure logic — asset selection, tag parsing, digest parsing, the byte[] decode — is cheap to test and is exactly where a silent wrong answer would ship a wrong artifact. Live-upstream runs stay in the plan as well; the tests are additive.

**3. `Get-AssetChecksum` is a fourth function the spec does not name.** The spec says consumers "should prefer" the asset's digest field but leaves the reading of it to the caller. Parsing `sha256:<hex>` deserves its own tested function, because the two failure modes — an absent field (fall back to hashing) and an unreadable field (a format change worth failing on) — must be distinguished, and inline code would likely collapse them.

---

### Task 0: Development environment

**Files:**
- Create: none (environment only)

**Interfaces:**
- Consumes: nothing
- Produces: a working `pwsh` with Pester 5 available, so every later task can run its tests locally

- [ ] **Step 1: Check whether pwsh is already present**

```bash
which pwsh || echo "not installed"
```

- [ ] **Step 2: Install PowerShell if missing**

```bash
brew install --cask powershell
```

If the cask install is refused or needs a password the user must supply, stop and ask the user to run it themselves with a `!` prefix. Do not work around it.

- [ ] **Step 3: Verify pwsh and install Pester**

```bash
pwsh -NoProfile -Command '$PSVersionTable.PSVersion; Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck; (Get-Module Pester -ListAvailable | Select-Object -First 1).Version'
```

Expected: a 7.x PowerShell version, then a Pester 5.x version.

- [ ] **Step 4: Create the tests directory with a placeholder-free smoke test**

Create `tests/Smoke.Tests.ps1`:

```powershell
Describe 'Pester harness' {
    It 'runs' {
        1 + 1 | Should -Be 2
    }
}
```

- [ ] **Step 5: Run it**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests -Output Detailed"`
Expected: 1 test passed.

- [ ] **Step 6: Commit**

```bash
git add tests/Smoke.Tests.ps1
git commit -m "test: add a Pester harness for the update scripts"
```

---

### Task 1: `scripts/ChocoUpdate.psm1`

**Files:**
- Create: `scripts/ChocoUpdate.psm1`
- Test: `tests/ChocoUpdate.Tests.ps1`
- Delete: `tests/Smoke.Tests.ps1` (its job is done once a real test file exists)

**Interfaces:**
- Consumes: nothing
- Produces:
  - `Get-ValidatedContent -Uri <string> -Validate <scriptblock> -What <string> [-Headers <hashtable>]` → whatever `$Validate` returns; throws after 4 failed attempts
  - `Get-DualArchSearchReplace -Latest <object>` → `hashtable` shaped for AU's `au_SearchReplace`

- [ ] **Step 1: Write the failing tests**

Create `tests/ChocoUpdate.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'ChocoUpdate.psm1') -Force
}

Describe 'Get-DualArchSearchReplace' {
    It 'produces replacements for all four variables' {
        $latest = @{
            URL64         = 'https://example.test/app-x64.exe'
            Checksum64    = 'aaaa'
            URLArm64      = 'https://example.test/app-arm64.exe'
            ChecksumArm64 = 'bbbb'
        }

        $sr = Get-DualArchSearchReplace -Latest $latest
        $rules = $sr['tools\chocolateyinstall.ps1']

        $rules.Count | Should -Be 4
        ($rules.Values -join ' ') | Should -BeLike '*app-x64.exe*'
        ($rules.Values -join ' ') | Should -BeLike '*app-arm64.exe*'
        ($rules.Values -join ' ') | Should -BeLike '*aaaa*'
        ($rules.Values -join ' ') | Should -BeLike '*bbbb*'
    }

    It 'rewrites a real install script line' {
        $latest = @{
            URL64 = 'https://example.test/new.exe'; Checksum64 = 'newsum'
            URLArm64 = 'https://example.test/new-arm.exe'; ChecksumArm64 = 'newarmsum'
        }
        $sr = Get-DualArchSearchReplace -Latest $latest
        $line = "  `$url64      = 'https://example.test/old.exe'"

        foreach ($pattern in $sr['tools\chocolateyinstall.ps1'].Keys) {
            $line = $line -replace $pattern, $sr['tools\chocolateyinstall.ps1'][$pattern]
        }

        $line | Should -BeLike "*'https://example.test/new.exe'*"
        $line | Should -Not -BeLike '*old.exe*'
    }
}

Describe 'Get-ValidatedContent' {
    It 'returns the validator result on the first success' {
        Mock -ModuleName ChocoUpdate Invoke-WebRequest {
            [pscustomobject]@{ Content = 'version: 1.2.3'; StatusCode = 200 }
        }

        $result = Get-ValidatedContent -Uri 'https://example.test/feed' -What 'the version' -Validate {
            param($body)
            $m = [regex]::Match($body, 'version: (\d+\.\d+\.\d+)')
            if ($m.Success) { $m.Groups[1].Value } else { $null }
        }

        $result | Should -Be '1.2.3'
    }

    It 'decodes a byte[] body as UTF-8' {
        Mock -ModuleName ChocoUpdate Invoke-WebRequest {
            [pscustomobject]@{
                Content    = [System.Text.Encoding]::UTF8.GetBytes('version: 9.9.9')
                StatusCode = 200
            }
        }

        $result = Get-ValidatedContent -Uri 'https://example.test/feed' -What 'the version' -Validate {
            param($body)
            $m = [regex]::Match($body, 'version: (\d+\.\d+\.\d+)')
            if ($m.Success) { $m.Groups[1].Value } else { $null }
        }

        $result | Should -Be '9.9.9'
    }

    It 'retries when the validator rejects the body, then succeeds' {
        $script:calls = 0
        Mock -ModuleName ChocoUpdate Start-Sleep { }
        Mock -ModuleName ChocoUpdate Invoke-WebRequest {
            $script:calls++
            $body = if ($script:calls -eq 1) { 'truncated' } else { 'value: ok' }
            [pscustomobject]@{ Content = $body; StatusCode = 200 }
        }

        $result = Get-ValidatedContent -Uri 'https://example.test/feed' -What 'the value' -Validate {
            param($body)
            if ($body -match 'value: (\w+)') { $Matches[1] } else { $null }
        }

        $result       | Should -Be 'ok'
        $script:calls | Should -Be 2
    }

    It 'throws with status, length and the body tail after every attempt fails' {
        Mock -ModuleName ChocoUpdate Start-Sleep { }
        Mock -ModuleName ChocoUpdate Invoke-WebRequest {
            [pscustomobject]@{ Content = 'nothing useful here'; StatusCode = 200 }
        }

        { Get-ValidatedContent -Uri 'https://example.test/feed' -What 'the value' -Validate { $null } } |
            Should -Throw -ExpectedMessage '*HTTP 200*'
    }

    It 'sends the headers it is given' {
        $script:seen = $null
        Mock -ModuleName ChocoUpdate Invoke-WebRequest {
            param($Uri, $Headers, $UseBasicParsing)
            $script:seen = $Headers
            [pscustomobject]@{ Content = 'ok'; StatusCode = 200 }
        }

        Get-ValidatedContent -Uri 'https://example.test/x' -What 'anything' `
            -Headers @{ 'Authorization' = 'Bearer t' } -Validate { param($b) $b } | Out-Null

        $script:seen['Authorization'] | Should -Be 'Bearer t'
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/ChocoUpdate.Tests.ps1 -Output Detailed"`
Expected: FAIL — the module file does not exist, so `Import-Module` errors in `BeforeAll`.

- [ ] **Step 3: Write the module**

Create `scripts/ChocoUpdate.psm1`:

```powershell
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/ChocoUpdate.Tests.ps1 -Output Detailed"`
Expected: PASS, 7 tests.

If `Mock -ModuleName ChocoUpdate` fails to intercept `Invoke-WebRequest`, the module name must match the file base name — confirm with `Get-Module ChocoUpdate`. Do not switch the tests to real HTTP.

- [ ] **Step 5: Remove the smoke test**

```bash
git rm tests/Smoke.Tests.ps1
```

- [ ] **Step 6: Commit**

```bash
git add scripts/ChocoUpdate.psm1 tests/ChocoUpdate.Tests.ps1
git commit -m "refactor: extract the shared AU fetch helper into a module

Both update scripts carried the same retrying, self-diagnosing fetch helper -
35 lines against 36, differing only in whether byte[] bodies were decoded. The
typeless variant is a strict superset, so it becomes the single copy. The
dual-arch au_SearchReplace table moves with it, since both packages emit the
identical four replacements."
```

---

### Task 2: `scripts/GitHubRelease.psm1`

**Files:**
- Create: `scripts/GitHubRelease.psm1`
- Test: `tests/GitHubRelease.Tests.ps1`

**Interfaces:**
- Consumes: `Get-ValidatedContent` from Task 1
- Produces:
  - `Get-GitHubLatestRelease -Repo <string>` → the parsed release object
  - `Get-ReleaseVersion -Release <object>` → `string` like `1.5.6`; throws on an unparseable tag
  - `Select-ReleaseAsset -Release <object> -Name <string>` → the single matching asset; throws on 0 or >1
  - `Get-AssetChecksum -Asset <object>` → lowercase hex `string`, or `$null` when the asset has no digest; throws when a digest exists but is not `sha256:<64 hex>`

- [ ] **Step 1: Write the failing tests**

Create `tests/GitHubRelease.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'ChocoUpdate.psm1')   -Force
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'GitHubRelease.psm1') -Force

    $script:sample = [pscustomobject]@{
        tag_name = 'v1.5.6'
        assets   = @(
            [pscustomobject]@{
                name   = 'jadx-1.5.6.zip'
                digest = 'sha256:545ea2be9c242511bc145755cf4bda2485ade42966e096f8b4d3da2a230e8974'
                browser_download_url = 'https://github.com/skylot/jadx/releases/download/v1.5.6/jadx-1.5.6.zip'
            },
            [pscustomobject]@{
                name   = 'jadx-gui-1.5.6-win.zip'
                digest = 'sha256:6e070b197d4e40275d10f6559a1661bdd2e2bb325e9ef4181c7ac1286b274d99'
                browser_download_url = 'https://github.com/skylot/jadx/releases/download/v1.5.6/jadx-gui-1.5.6-win.zip'
            }
        )
    }
}

Describe 'Get-ReleaseVersion' {
    It 'strips a leading v' {
        Get-ReleaseVersion -Release $script:sample | Should -Be '1.5.6'
    }

    It 'accepts a tag with no v' {
        Get-ReleaseVersion -Release ([pscustomobject]@{ tag_name = '2.0.1' }) | Should -Be '2.0.1'
    }

    It 'accepts a two-component version' {
        Get-ReleaseVersion -Release ([pscustomobject]@{ tag_name = 'v3.1' }) | Should -Be '3.1'
    }

    It 'throws on a tag that carries no version' {
        { Get-ReleaseVersion -Release ([pscustomobject]@{ tag_name = 'nightly' }) } |
            Should -Throw -ExpectedMessage '*nightly*'
    }
}

Describe 'Select-ReleaseAsset' {
    It 'returns the one asset whose name matches exactly' {
        $asset = Select-ReleaseAsset -Release $script:sample -Name 'jadx-1.5.6.zip'
        $asset.browser_download_url | Should -BeLike '*/jadx-1.5.6.zip'
    }

    It 'does not match on a prefix' {
        { Select-ReleaseAsset -Release $script:sample -Name 'jadx-1.5.6' } |
            Should -Throw -ExpectedMessage '*found 0*'
    }

    It 'lists the available assets when nothing matches' {
        { Select-ReleaseAsset -Release $script:sample -Name 'missing.zip' } |
            Should -Throw -ExpectedMessage '*jadx-gui-1.5.6-win.zip*'
    }

    It 'throws when more than one asset matches' {
        $dup = [pscustomobject]@{
            tag_name = 'v1.0.0'
            assets   = @(
                [pscustomobject]@{ name = 'same.zip' },
                [pscustomobject]@{ name = 'same.zip' }
            )
        }
        { Select-ReleaseAsset -Release $dup -Name 'same.zip' } |
            Should -Throw -ExpectedMessage '*found 2*'
    }
}

Describe 'Get-AssetChecksum' {
    It 'returns the hex digest without the algorithm prefix' {
        $asset = Select-ReleaseAsset -Release $script:sample -Name 'jadx-1.5.6.zip'
        Get-AssetChecksum -Asset $asset |
            Should -Be '545ea2be9c242511bc145755cf4bda2485ade42966e096f8b4d3da2a230e8974'
    }

    It 'returns null when the asset has no digest' {
        Get-AssetChecksum -Asset ([pscustomobject]@{ name = 'x.zip' }) | Should -BeNullOrEmpty
    }

    It 'throws on a digest algorithm it cannot read' {
        { Get-AssetChecksum -Asset ([pscustomobject]@{ name = 'x.zip'; digest = 'md5:abc' }) } |
            Should -Throw -ExpectedMessage '*md5:abc*'
    }
}

Describe 'Get-GitHubLatestRelease' {
    It 'parses the JSON body and returns the release' {
        Mock -ModuleName ChocoUpdate Invoke-WebRequest {
            [pscustomobject]@{
                StatusCode = 200
                Content    = '{"tag_name":"v1.5.6","assets":[{"name":"jadx-1.5.6.zip"}]}'
            }
        }

        $release = Get-GitHubLatestRelease -Repo 'skylot/jadx'
        $release.tag_name       | Should -Be 'v1.5.6'
        $release.assets[0].name | Should -Be 'jadx-1.5.6.zip'
    }

    It 'sends an Authorization header when GITHUB_TOKEN is set' {
        $script:seen = $null
        Mock -ModuleName ChocoUpdate Invoke-WebRequest {
            param($Uri, $Headers, $UseBasicParsing)
            $script:seen = $Headers
            [pscustomobject]@{ StatusCode = 200; Content = '{"tag_name":"v1.0.0","assets":[{"name":"a"}]}' }
        }

        $env:GITHUB_TOKEN = 'test-token'
        try {
            Get-GitHubLatestRelease -Repo 'owner/repo' | Out-Null
        } finally {
            Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
        }

        $script:seen['Authorization'] | Should -Be 'Bearer test-token'
        $script:seen['Accept']        | Should -Be 'application/vnd.github+json'
    }

    It 'omits Authorization when GITHUB_TOKEN is absent' {
        $script:seen = $null
        Mock -ModuleName ChocoUpdate Invoke-WebRequest {
            param($Uri, $Headers, $UseBasicParsing)
            $script:seen = $Headers
            [pscustomobject]@{ StatusCode = 200; Content = '{"tag_name":"v1.0.0","assets":[{"name":"a"}]}' }
        }

        Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
        Get-GitHubLatestRelease -Repo 'owner/repo' | Out-Null

        $script:seen.ContainsKey('Authorization') | Should -BeFalse
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/GitHubRelease.Tests.ps1 -Output Detailed"`
Expected: FAIL — `GitHubRelease.psm1` does not exist.

- [ ] **Step 3: Write the module**

Create `scripts/GitHubRelease.psm1`:

```powershell
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/GitHubRelease.Tests.ps1 -Output Detailed"`
Expected: PASS, 14 tests.

- [ ] **Step 5: Check the spec's transitive-import claim empirically**

Run:

```bash
pwsh -NoProfile -Command "Import-Module ./scripts/GitHubRelease.psm1 -Force; if (Get-Command Get-ValidatedContent -ErrorAction SilentlyContinue) { 'transitive: yes' } else { 'transitive: no' }"
```

Record the answer. If it prints `transitive: no`, the spec's claim is wrong and Task 6 must import both modules — which it already does. Either way, note the result in the Task 6 commit message.

- [ ] **Step 6: Verify against the live API once**

Run:

```bash
pwsh -NoProfile -Command "Import-Module ./scripts/ChocoUpdate.psm1 -Force; Import-Module ./scripts/GitHubRelease.psm1 -Force; \$r = Get-GitHubLatestRelease -Repo 'skylot/jadx'; \$v = Get-ReleaseVersion -Release \$r; \$a = Select-ReleaseAsset -Release \$r -Name \"jadx-\$v.zip\"; \"\$v \$(Get-AssetChecksum -Asset \$a)\""
```

Expected: `1.5.6 545ea2be9c242511bc145755cf4bda2485ade42966e096f8b4d3da2a230e8974` — the checksum must equal the SHA-256 the previous maintainer recorded in VERIFICATION.txt.

- [ ] **Step 7: Commit**

```bash
git add scripts/GitHubRelease.psm1 tests/GitHubRelease.Tests.ps1
git commit -m "feat: add a GitHub Releases source adapter for AU scripts

Resolves the latest release, reads the version from the tag, selects an asset
by exact name, and takes the checksum from the asset's digest field so no
download is needed to hash it. Ambiguous asset matches and unreadable digests
throw rather than guess, because either would publish the wrong artifact."
```

---

### Task 3: Migrate `antigravity-ide`

**Files:**
- Modify: `antigravity-ide/update.ps1` (remove the inlined helper and the dual-arch table)

**Interfaces:**
- Consumes: `Get-ValidatedContent`, `Get-DualArchSearchReplace` from Task 1
- Produces: nothing new — this task must be behaviour-neutral

- [ ] **Step 1: Record the current behaviour as the baseline**

The nuspec is at 2.5.5 and upstream is at 2.5.5, so the script must report no update and must not write any file.

```bash
git status --porcelain            # expect empty
pwsh -NoProfile -Command "./antigravity-ide/update.ps1" 2>&1 | tee /tmp/agi-before.txt
git status --porcelain            # expect still empty: no update, nothing rewritten
tail -5 /tmp/agi-before.txt
```

Expected: the AU summary reports no update, and `git status` stays clean. If a `.nupkg` appeared, upstream moved — stop and re-baseline before continuing, because the comparison in Step 4 would then be against a moving target.

- [ ] **Step 2: Rewrite the script against the module**

Replace the whole of `antigravity-ide/update.ps1` with:

```powershell
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
Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'ChocoUpdate.psm1') -Force

$ErrorActionPreference = 'Stop'

# AU resolves the .nuspec relative to the current directory.
Set-Location -Path $PSScriptRoot

$DownloadPage = 'https://antigravity.google/download'
$Stable       = 'https://edgedl\.me\.gvt1\.com/edgedl/release2/j0qc3/antigravity/stable'

function global:au_GetLatest {
    # Both per-arch IDE installer URLs are plain string literals in the download
    # page's HTML, e.g.
    #   .../stable/2.1.1-6123990880747520/windows-x64/Antigravity%20IDE.exe
    # The $Stable anchor pins the match to the edgedl .../antigravity/stable/
    # path so we never pick up the unrelated antigravity-hub build that the same
    # page links from storage.googleapis.com.
    #
    # antigravity.google is served through Google Frontend with a 10-minute
    # shared edge cache, and it occasionally answers 200 with a body that is
    # missing the markup we scrape (observed ~3% of CI runs). Get-ValidatedContent
    # retries those.
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
    Get-DualArchSearchReplace -Latest $Latest
}

# Checksums are computed in au_BeforeUpdate, so disable AU's own checksum step.
# -NoReadme: AU otherwise overwrites the nuspec <description> with the package
# folder's README.md (minus its first 2 lines). We keep a hand-curated,
# user-facing <description> in the nuspec, so opt out of that behaviour.
Update-Package -ChecksumFor none -NoReadme
```

Note that `$Stable` is referenced from inside the `-Validate` scriptblock. Scriptblocks passed to a module function still close over the caller's scope, so this keeps working — Step 3 is what proves it.

- [ ] **Step 3: Run it and compare against the baseline**

```bash
pwsh -NoProfile -Command "./antigravity-ide/update.ps1" 2>&1 | tee /tmp/agi-after.txt
git status --porcelain            # expect empty, exactly as before
diff <(grep -E '^(antigravity-ide|no updates|Updated)' /tmp/agi-before.txt) \
     <(grep -E '^(antigravity-ide|no updates|Updated)' /tmp/agi-after.txt) && echo "same verdict"
```

Expected: the same "no update" verdict, and a still-clean working tree. A `Could not find the windows-x64/arm64 installer URLs` throw means the scriptblock lost its closure over `$Stable` — fix by passing the anchor into the validator rather than by inlining the helper again.

- [ ] **Step 4: Confirm the line count actually dropped**

```bash
sed 's/#.*//' antigravity-ide/update.ps1 | grep -vE '^\s*$' | wc -l
```

Expected: roughly 45 lines, down from 96.

- [ ] **Step 5: Commit**

```bash
git add antigravity-ide/update.ps1
git commit -m "refactor: move antigravity-ide onto the shared update module

The scrape in au_GetLatest is unchanged; everything below it now comes from
scripts/ChocoUpdate.psm1. Verified against the live download page: the script
still reports no update at 2.5.5 and leaves the working tree clean."
```

---

### Task 4: Migrate `typeless`

**Files:**
- Modify: `typeless/update.ps1` (remove the inlined helper and the dual-arch table)

**Interfaces:**
- Consumes: `Get-ValidatedContent`, `Get-DualArchSearchReplace` from Task 1
- Produces: nothing new — behaviour-neutral

This is the more valuable of the two migrations: the nuspec is at 2.1.0 while upstream is ahead, so running the script exercises the whole update path — feed parse, base64-to-hex conversion, and the rewrite of `tools/chocolateyinstall.ps1`.

- [ ] **Step 1: Capture what the pre-migration script produces**

```bash
git status --porcelain                        # expect empty
pwsh -NoProfile -Command "./typeless/update.ps1"
cp typeless/tools/chocolateyinstall.ps1 /tmp/typeless-install-before.ps1
grep -o '<version>[^<]*' typeless/typeless.nuspec | tee /tmp/typeless-version-before.txt
git status --porcelain                        # expect the nuspec and install script modified
```

- [ ] **Step 2: Restore the working tree**

```bash
git checkout -- typeless/
rm -f typeless/*.nupkg
git status --porcelain                        # expect empty again
```

The `.nupkg` is untracked, so `git checkout` will not remove it; delete it explicitly or Task 4's CI-shaped "Detect built package" logic would pick up a stale artifact.

- [ ] **Step 3: Rewrite the script against the module**

Replace the whole of `typeless/update.ps1` with:

```powershell
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
Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'ChocoUpdate.psm1') -Force

$ErrorActionPreference = 'Stop'

# AU resolves the .nuspec relative to the current directory.
Set-Location -Path $PSScriptRoot

$ReleaseBase = 'https://typeless-static.com/desktop-release'

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

  The feeds are served as application/x-www-form-urlencoded, so the body arrives
  as a byte[]; Get-ValidatedContent decodes it as UTF-8 before we see it.
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
    Get-DualArchSearchReplace -Latest $Latest
}

# Checksums come from the upstream feed (see au_GetLatest), so disable AU's own
# checksum step - it would re-download both installers to recompute them.
# -NoReadme: AU otherwise overwrites the nuspec <description> with the package
# folder's README.md (minus its first 2 lines). We keep a hand-curated,
# user-facing <description> in the nuspec, so opt out of that behaviour.
Update-Package -ChecksumFor none -NoReadme
```

`Get-ReleaseFeed` keeps its `global:` prefix: it is called from `global:au_GetLatest`, which AU invokes in the global scope.

- [ ] **Step 4: Run it and diff the generated install script against the baseline**

```bash
pwsh -NoProfile -Command "./typeless/update.ps1"
diff /tmp/typeless-install-before.ps1 typeless/tools/chocolateyinstall.ps1 && echo "IDENTICAL"
grep -o '<version>[^<]*' typeless/typeless.nuspec
cat /tmp/typeless-version-before.txt
```

Expected: `IDENTICAL`, and the same version in both. This is the real regression test for the migration — the same four URL/checksum substitutions, byte for byte.

If upstream published a new version between Step 1 and Step 4 the diff will show a version change rather than a defect; re-run Step 1 through Step 4 back to back and compare again.

- [ ] **Step 5: Restore the working tree**

The result must not be committed: 2.1.0 is still in moderation and this repository publishes only what CI publishes.

```bash
git checkout -- typeless/
rm -f typeless/*.nupkg
git status --porcelain            # expect only typeless/update.ps1 modified
```

- [ ] **Step 6: Confirm the line count dropped**

```bash
sed 's/#.*//' typeless/update.ps1 | grep -vE '^\s*$' | wc -l
```

Expected: roughly 70 lines, down from 126.

- [ ] **Step 7: Commit**

```bash
git add typeless/update.ps1
git commit -m "refactor: move typeless onto the shared update module

au_GetLatest and the feed parser are unchanged; the fetch helper and the
dual-arch replacement table now come from scripts/ChocoUpdate.psm1. Verified by
running the update path against the live feeds before and after: the rewritten
tools/chocolateyinstall.ps1 is byte-identical."
```

---

### Task 5: The jadx package files

**Files:**
- Create: `jadx/jadx.nuspec`
- Create: `jadx/tools/chocolateyinstall.ps1`
- Create: `jadx/tools/chocolateyuninstall.ps1`
- Create: `jadx/README.md`
- Create: `jadx/icon.png`

**Interfaces:**
- Consumes: nothing (these files are consumed by Chocolatey, not by other tasks)
- Produces: a package directory that `choco pack` accepts, with `$url64` / `$checksum64` lines that Task 6's `au_SearchReplace` rewrites

⚠️ **CPMR0010 applies to the text of these scripts, not just to what they execute.** The rule is a plain string match for `cinst`, `choco install` and `choco upgrade`, and the docs say it "can also hit a false positive if it finds any of the above words in the package's automation scripts". The Java warning must therefore name JDK distributions **without** writing an install command — say "install a JDK such as Temurin or Zulu", never the command line.

- [ ] **Step 1: Fetch the icon from upstream**

```bash
curl -sL "https://raw.githubusercontent.com/skylot/jadx/master/jadx-gui/src/main/resources/logos/jadx-logo.png" -o jadx/icon.png
file jadx/icon.png
```

Expected: `PNG image data`. If that path 404s, list the logos directory and pick the largest square PNG:

```bash
curl -s "https://api.github.com/repos/skylot/jadx/contents/jadx-gui/src/main/resources/logos" | python3 -c "import json,sys; [print(f['name'], f['size']) for f in json.load(sys.stdin)]"
```

The upstream repo is Apache-2.0, so redistributing the logo in the package listing is permitted.

- [ ] **Step 2: Write the nuspec**

Create `jadx/jadx.nuspec`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2015/06/nuspec.xsd">
  <metadata>
    <id>jadx</id>
    <version>1.5.6</version>
    <packageSourceUrl>https://github.com/moscowmule2240/chocolatey-packages/tree/main/jadx</packageSourceUrl>
    <owners>moscowmule2240</owners>

    <title>JADX (Portable)</title>
    <authors>Skylot</authors>
    <projectUrl>https://github.com/skylot/jadx</projectUrl>
    <iconUrl>https://cdn.jsdelivr.net/gh/moscowmule2240/chocolatey-packages@main/jadx/icon.png</iconUrl>
    <copyright>Skylot</copyright>
    <licenseUrl>https://github.com/skylot/jadx/blob/master/LICENSE</licenseUrl>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <bugTrackerUrl>https://github.com/skylot/jadx/issues</bugTrackerUrl>
    <docsUrl>https://github.com/skylot/jadx/wiki</docsUrl>
    <tags>java decompiler android dex apk smali reverse-engineering foss</tags>
    <summary>Command line and GUI tools to produce Java source code from Android Dex and Apk files.</summary>
    <description><![CDATA[
JADX decompiles Dalvik bytecode to Java source from APK, dex, aar, aab and zip
files, and decodes AndroidManifest.xml and other resources from `resources.arsc`.
It ships both a command line tool (`jadx`) and a GUI (`jadx-gui`) with code
navigation, search and deobfuscation.

This is a portable package: it unpacks the official release archive and registers
`jadx` and `jadx-gui` on PATH.

### Java is required and is not installed by this package

jadx needs **Java 11 or later, 64-bit**. This package does not declare a Java
dependency, because the Chocolatey Community Repository has no package that means
"any Java 11 or later" — the `javaruntime` metapackage resolves to Java 8, which
jadx cannot run on. Depending on one specific JDK id would install a second JDK
for the many users who already have one.

If Java is missing or too old, installation still succeeds and a warning is
printed; jadx will not start until a suitable JDK is on PATH. Any 64-bit Java 11+
distribution works — for example Temurin, Zulu, Microsoft Build of OpenJDK, or
Oracle's.
]]></description>
    <releaseNotes>https://github.com/skylot/jadx/releases</releaseNotes>
  </metadata>
  <files>
    <file src="tools\**" target="tools" />
  </files>
</package>
```

There is no `<dependencies>` element and no `projectSourceUrl` — both are deliberate; see the spec's findings 2, 3 and 6.

- [ ] **Step 3: Write the install script**

Create `jadx/tools/chocolateyinstall.ps1`. This runs under **Windows PowerShell 5.1**, so keep to 5.1-compatible syntax:

```powershell
$ErrorActionPreference = 'Stop'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Rewritten by ../update.ps1 on every release; the checksum comes from the
# GitHub release asset's digest field, so it is the hash GitHub itself records.
$url64      = 'https://github.com/skylot/jadx/releases/download/v1.5.6/jadx-1.5.6.zip'
$checksum64 = '545ea2be9c242511bc145755cf4bda2485ade42966e096f8b4d3da2a230e8974'

# The archive is Java bytecode and architecture-independent: one artifact serves
# both x64 and arm64, so only the 64-bit parameters are set.
Install-ChocolateyZipPackage `
    -PackageName    $env:ChocolateyPackageName `
    -Url64bit       $url64 `
    -Checksum64     $checksum64 `
    -ChecksumType64 'sha256' `
    -UnzipLocation  $toolsDir

# The archive unpacks to jadx-<version>/, so locate bin/ rather than assuming it.
$binPath = Get-ChildItem -Path $toolsDir -Directory -Recurse -Filter 'bin' |
           Where-Object { Test-Path (Join-Path $_.FullName 'jadx.bat') } |
           Select-Object -First 1 -ExpandProperty FullName
if (-not $binPath) { throw "Could not find bin\jadx.bat under $toolsDir after unpacking." }

$jadx    = Join-Path $binPath 'jadx.bat'
$jadxGui = Join-Path $binPath 'jadx-gui.bat'

Install-BinFile -Name 'jadx'     -Path $jadx
Install-BinFile -Name 'jadx-gui' -Path $jadxGui

if (Test-ProcessAdminRights) {
    $specialFolder = [Environment+SpecialFolder]::CommonPrograms
} else {
    $specialFolder = [Environment+SpecialFolder]::Programs
}
$linkPath = Join-Path ([Environment]::GetFolderPath($specialFolder)) 'JADX GUI.lnk'
Install-ChocolateyShortcut -ShortcutFilePath $linkPath -TargetPath $jadxGui

# Java check. This warns and never throws: unpacking and shimming do not need
# Java, and failing here would make the package uninstallable on the Chocolatey
# verifier, which runs without a JDK. jadx itself reports a clear error when it
# is started without a suitable runtime.
$javaRequirement = 'jadx requires 64-bit Java 11 or later. Any distribution works - for example Temurin, Zulu, the Microsoft Build of OpenJDK, or Oracle Java.'
$java = Get-Command 'java.exe' -ErrorAction SilentlyContinue

if (-not $java) {
    Write-Warning "Java was not found on PATH. $javaRequirement"
} else {
    $versionOutput = & $java.Source -version 2>&1 | Out-String

    # 'java version "1.8.0_401"' for 8 and older, 'openjdk version "21.0.1"' for 9+.
    $m = [regex]::Match($versionOutput, 'version "(\d+)(?:\.(\d+))?')
    if ($m.Success) {
        $major = [int]$m.Groups[1].Value
        if ($major -eq 1 -and $m.Groups[2].Success) { $major = [int]$m.Groups[2].Value }

        if ($major -lt 11) {
            Write-Warning "Java $major was found on PATH. $javaRequirement"
        }
    } else {
        Write-Warning "Could not read the version from 'java -version'. $javaRequirement"
    }

    if ($versionOutput -notmatch '64-Bit') {
        Write-Warning "The Java on PATH does not report a 64-bit VM. $javaRequirement"
    }
}
```

- [ ] **Step 4: Write the uninstall script**

Create `jadx/tools/chocolateyuninstall.ps1`:

```powershell
$ErrorActionPreference = 'Stop'

# Shims created with Install-BinFile are not removed automatically.
Uninstall-BinFile -Name 'jadx'
Uninstall-BinFile -Name 'jadx-gui'

if (Test-ProcessAdminRights) {
    $specialFolder = [Environment+SpecialFolder]::CommonPrograms
} else {
    $specialFolder = [Environment+SpecialFolder]::Programs
}
$linkPath = Join-Path ([Environment]::GetFolderPath($specialFolder)) 'JADX GUI.lnk'
if (Test-Path $linkPath) { Remove-Item -Path $linkPath -Force }
```

- [ ] **Step 5: Write the package README**

Create `jadx/README.md`, following the shape of the existing two package READMEs:

```markdown
# jadx

[JADX](https://github.com/skylot/jadx) — command line and GUI tools that produce
Java source code from Android Dex and Apk files.

## Upstream

Releases: <https://github.com/skylot/jadx/releases>

The package installs `jadx-<version>.zip`, the standard release archive that
carries both `bin/jadx` and `bin/jadx-gui`. The `-with-jre-win` archive is not
used: no other distribution ships it, and it would add ~25 MB of JRE for users
who almost always already have Java.

## Java

jadx requires 64-bit Java 11 or later, and this package does not declare a Java
dependency.

The Chocolatey Community Repository has no package meaning "any Java 11 or
later". The `javaruntime` metapackage resolves to `jre8`, which is too old for
jadx, and Chocolatey's virtual-package feature — which would let one dependency
be satisfied by any of several JDKs — is documented as not yet implemented.
Depending on a specific id such as `temurin11` would install a second JDK
alongside whatever the user already runs.

Every other Java 11+ tool on the repository does the same. `ghidra`, `zap`,
`jenkins` and `openrefine` all declare no Java dependency.

The install script detects Java and prints a warning when it is missing or older
than 11. It does not fail the installation: unpacking and shim registration do
not need Java.

## Maintenance notes

- `update.ps1` reads the latest GitHub release through
  `scripts/GitHubRelease.psm1`. The checksum comes from the release asset's
  `digest` field, so no download is needed to hash the 69 MB archive.
- The archive unpacks to `jadx-<version>/`, so the install script searches for
  `bin/jadx.bat` rather than assuming a fixed path — the directory name changes
  with every release.
- Shims are registered explicitly with `Install-BinFile` and must be removed
  explicitly with `Uninstall-BinFile`.
```

- [ ] **Step 6: Verify the package builds and the metadata is well-formed**

```bash
python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('jadx/jadx.nuspec'); print('nuspec parses')"
if grep -rnE 'cinst|choco (install|upgrade)' jadx/; then
  echo "CPMR0010: FOUND - rewrite the text above"
else
  echo "CPMR0010: clean"
fi
```

Expected: `nuspec parses` and `CPMR0010: clean`. Only `tools\**` is packaged, so the validator sees just the two scripts — but the search covers the whole `jadx/` directory anyway, because a phrase that reads well in the README tends to get copied into a warning string later. A match even inside a comment is flagged as a Requirement failure. If it reports FOUND, rewrite the text; do not keep it because "it's only a comment".

- [ ] **Step 7: Commit**

```bash
git add jadx/
git commit -m "feat: add the jadx package

Downloads the standard release archive at install time and shims both jadx and
jadx-gui, following the existing Chocolatey package and Scoop.

No Java dependency is declared. jadx needs Java 11+, the javaruntime metapackage
resolves to Java 8, and Chocolatey's virtual packages - which would let any
sufficient JDK satisfy one dependency - are documented as not implemented.
Pinning a specific JDK id would install a redundant second JDK for most users,
and it was a JDK dependency that failed verification on the last two upstream
releases. The install script warns about a missing or old Java instead of
failing, so unpacking still succeeds where no JDK is present."
```

---

### Task 6: `jadx/update.ps1`

**Files:**
- Create: `jadx/update.ps1`

**Interfaces:**
- Consumes: `Get-GitHubLatestRelease`, `Get-ReleaseVersion`, `Select-ReleaseAsset`, `Get-AssetChecksum` from Task 2; the `$url64` / `$checksum64` lines from Task 5
- Produces: nothing consumed by later tasks

- [ ] **Step 1: Write the script**

Create `jadx/update.ps1`:

```powershell
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
    # jadx-gui-<version>-with-jre-win.zip, and a prefix match would pick one of
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
```

- [ ] **Step 2: Run it against the live API with the nuspec already current**

The nuspec written in Task 5 is at 1.5.6, which is the current release, so this must be a no-op.

```bash
git status --porcelain                      # expect empty
pwsh -NoProfile -Command "./jadx/update.ps1"
git status --porcelain                      # expect still empty
```

Expected: AU reports no update, and nothing is rewritten. A rewrite here means `au_GetLatest` produced a different version or URL than Task 5 hard-coded — compare them before continuing.

- [ ] **Step 3: Prove the update path by rolling the nuspec back**

```bash
sed -i '' 's|<version>1.5.6</version>|<version>1.5.5</version>|' jadx/jadx.nuspec
pwsh -NoProfile -Command "./jadx/update.ps1"
grep -o '<version>[^<]*' jadx/jadx.nuspec
grep -E '^\$(url64|checksum64)' jadx/tools/chocolateyinstall.ps1
ls jadx/*.nupkg
```

Expected: the nuspec is back at `1.5.6`, `$url64` ends in `/v1.5.6/jadx-1.5.6.zip`, `$checksum64` is `545ea2be…`, and a `.nupkg` was produced. Confirm from the console output that no 69 MB download occurred — the digest path must have supplied the checksum.

- [ ] **Step 4: Clean up the build artifacts**

```bash
rm -f jadx/*.nupkg
git checkout -- jadx/jadx.nuspec jadx/tools/chocolateyinstall.ps1
git status --porcelain                      # expect only jadx/update.ps1 untracked
```

- [ ] **Step 5: Commit**

```bash
git add jadx/update.ps1
git commit -m "feat: drive the jadx package from the GitHub releases adapter

Takes the checksum from the release asset's digest field, so a version bump
costs one API call instead of a 69 MB download. The archive is
architecture-independent, so this package writes its own two-line
au_SearchReplace rather than using the dual-arch helper."
```

---

### Task 7: `.github/workflows/update-jadx.yml`

**Files:**
- Create: `.github/workflows/update-jadx.yml`
- Reference: `.github/workflows/update-typeless.yml` (copy its shape)

**Interfaces:**
- Consumes: `jadx/update.ps1` from Task 6, `scripts/Check-ChocolateyStatus.ps1` (existing)
- Produces: nothing consumed by later tasks

- [ ] **Step 1: Copy the typeless workflow as the starting point**

```bash
cp .github/workflows/update-typeless.yml .github/workflows/update-jadx.yml
```

- [ ] **Step 2: Adjust it for jadx**

Make exactly these changes, leaving every other step untouched:

1. `name:` → `Update jadx`
2. `env: PKG_DIR:` → `jadx`
3. Keep the `schedule:` block commented out, and replace the comment above it with:

```yaml
  # Enabled once the maintainer handover for the existing jadx package
  # completes. See docs/superpowers/specs/2026-08-22-au-shared-modules-design.md.
  # schedule:
  #   - cron: "*/5 * * * *"    # every 5 minutes
```

4. Add `GITHUB_TOKEN` to the AU step so `Get-GitHubLatestRelease` authenticates:

```yaml
      - name: Run AU update (detect + repack if newer)
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: '& "./$env:PKG_DIR/update.ps1"'
```

- [ ] **Step 3: Verify the YAML parses and the substitutions are complete**

```bash
python3 -c "
import sys
try:
    import yaml
except ImportError:
    sys.exit('pyyaml not installed; run: python3 -m pip install --user pyyaml')
d = yaml.safe_load(open('.github/workflows/update-jadx.yml'))
print('name:', d['name'])
job = list(d['jobs'].values())[0]
print('PKG_DIR:', job['env']['PKG_DIR'])
print('schedule present:', 'schedule' in (d.get(True) or d.get('on') or {}))
"
grep -n "typeless" .github/workflows/update-jadx.yml || echo "no leftover typeless references"
grep -n "GITHUB_TOKEN" .github/workflows/update-jadx.yml
```

Expected: `name: Update jadx`, `PKG_DIR: jadx`, `schedule present: False`, no leftover `typeless`, and one `GITHUB_TOKEN` line. Note that PyYAML parses the YAML key `on:` as the boolean `True`, which is why the check looks under both keys.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/update-jadx.yml
git commit -m "ci: add the jadx update workflow

Mirrors the other two packages. The schedule stays commented out until the
maintainer handover completes, matching how typeless was introduced. GITHUB_TOKEN
is passed to the AU step because the unauthenticated GitHub API limit is metered
per IP address and shared runners exhaust it."
```

---

### Task 8: Run the tests in CI

**Files:**
- Create: `.github/workflows/test.yml`

**Interfaces:**
- Consumes: `tests/*.Tests.ps1` from Tasks 1 and 2
- Produces: nothing consumed by later tasks

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/test.yml`:

```yaml
name: Tests

on:
  push:
    branches: [main]
    paths:
      - 'scripts/**'
      - 'tests/**'
      - '*/update.ps1'
      - '.github/workflows/test.yml'
  pull_request:
    paths:
      - 'scripts/**'
      - 'tests/**'
      - '*/update.ps1'
      - '.github/workflows/test.yml'
  workflow_dispatch:

permissions:
  contents: read

jobs:
  pester:
    # windows-latest matches where the update scripts actually run, so a
    # PowerShell difference between platforms cannot hide here.
    runs-on: windows-latest
    defaults:
      run:
        shell: pwsh

    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: Install Pester
        run: Install-PSResource -Name Pester -TrustRepository

      - name: Run Pester
        run: |
          $result = Invoke-Pester -Path ./tests -Output Detailed -PassThru
          if ($result.FailedCount -gt 0) {
            Write-Error "$($result.FailedCount) test(s) failed"
            exit 1
          }
          Write-Host "$($result.PassedCount) test(s) passed"
```

- [ ] **Step 2: Verify the YAML parses**

```bash
python3 -c "
import yaml
d = yaml.safe_load(open('.github/workflows/test.yml'))
print('name:', d['name'])
print('runs-on:', d['jobs']['pester']['runs-on'])
print('steps:', len(d['jobs']['pester']['steps']))
"
```

Expected: `name: Tests`, `runs-on: windows-latest`, `steps: 3`.

- [ ] **Step 3: Run the whole suite locally one more time**

```bash
pwsh -NoProfile -Command "Invoke-Pester ./tests -Output Detailed"
```

Expected: all tests pass, 21 total (7 from Task 1, 14 from Task 2).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "ci: run the Pester suite on scripts and update-script changes

Runs on windows-latest, the same platform as the update workflows, so a
PowerShell behaviour difference between platforms cannot hide in the tests."
```

---

## Verification after all tasks

- [ ] `pwsh -NoProfile -Command "Invoke-Pester ./tests -Output Detailed"` — all green.
- [ ] `pwsh -NoProfile -Command "./antigravity-ide/update.ps1"` — no update, clean tree.
- [ ] `pwsh -NoProfile -Command "./jadx/update.ps1"` — no update, clean tree.
- [ ] `git status --porcelain` — empty. No `.nupkg` left behind anywhere.
- [ ] `sed 's/#.*//' */update.ps1 | grep -vE '^\s*$' | wc -l` — materially below the 222 lines the two scripts held before.
- [ ] Push the branch and confirm the `Tests` workflow goes green on `windows-latest`. This is the only place the modules run on the platform they were written for; a local pass on macOS is necessary but not sufficient.
- [ ] Do **not** enable the jadx schedule, and do **not** push any package to Chocolatey. The handover response window ends 2026-08-29.

## Follow-up, once the handover completes

Not part of this plan — recorded so it is not lost:

1. Ask the Site Admins to move jadx 1.5.6 from `rejected` back to `submitted`, as the rejection notice describes.
2. Uncomment `schedule:` in `.github/workflows/update-jadx.yml`.
3. Watch the first scheduled run through to a Chocolatey push, as was done for antigravity-ide.

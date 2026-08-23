# radare2 Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `radare2/` package at 6.2.0 that can replace the five-year-old one on the Chocolatey Community Repository as soon as maintainer access is granted.

**Architecture:** Same shape as `jadx/`. `update.ps1` drives `scripts/GitHubRelease.psm1` to resolve the release, pick three per-architecture assets and read their checksums from the asset digests. `tools/chocolateyinstall.ps1` selects one archive at install time, unpacks it, and registers a single explicit shim; the other sixteen executables are left to Chocolatey's automatic `.exe` shims.

**Tech Stack:** PowerShell 7 (`pwsh`) for `update.ps1` and tests, Windows PowerShell 5.1 for the install scripts, Pester 5, Chocolatey AU, GitHub Actions on `windows-latest`.

**Spec:** `docs/superpowers/specs/2026-08-23-radare2-package-design.md`

## Global Constraints

- **Two PowerShell dialects.** `update.ps1` and the modules run under `pwsh` 7. `tools/*.ps1` are executed by Chocolatey under **Windows PowerShell 5.1** — no ternary `? :`, no `??`, and they must not import the repository's modules.
- **AU calls `au_*` in the global scope.** Keep the `global:` prefix on `au_GetLatest`, `au_BeforeUpdate` and `au_SearchReplace`; import modules with plain `Import-Module ... -Force`, never `-Scope Local`.
- **CPMR0010 is a plain string match** for `cinst`, `choco install` and `choco upgrade`. Those strings must not appear anywhere under `radare2/`, comments included.
- **`checksumType` is `sha256`** for all three archives — that is what the release asset `digest` field carries.
- **Nothing is published until the handover completes.** `.github/workflows/update-radare2.yml` ships with `schedule:` commented out.
- **Do not commit a radare2 logo.** `radareorg/radare.org` has no license file; `iconUrl` keeps pointing at the upstream CDN copy.
- **Commit messages** follow the repository style: lowercase `<scope>: <imperative summary>`, English, no first person.

## Execution environment

The executing machine has **no `pwsh`**; Windows handles real-machine testing. Every step below that would run PowerShell is redirected:

| Would run | Actually do |
| --- | --- |
| `Invoke-Pester` | The `Tests` workflow runs it on `windows-latest` after the push. Until it does, the tests are unverified — say so rather than implying they passed. |
| `./radare2/update.ps1` | Verify through `workflow_dispatch` on the package's own workflow, or on the Windows machine. |
| `choco pack` / `choco install` | Windows machine only. **Re-run `choco pack` after every fix** — `choco install -s .` reads the `.nupkg`, not the working tree. |

Locally verifiable, and therefore mandatory: XML and YAML parse, the six replacement patterns behave against the real install script, the CPMR0010 string scan, and brace/quote balance in every `.ps1`.

## File Structure

| File | Responsibility |
| --- | --- |
| `radare2/radare2.nuspec` | Metadata. No `<dependencies>`; `description` carried over from the existing package minus one stale line |
| `radare2/tools/chocolateyinstall.ps1` | Picks one of three archives, unpacks, registers the `r2` alias |
| `radare2/tools/chocolateyuninstall.ps1` | Removes the `r2` alias — one line |
| `radare2/update.ps1` | AU script over `GitHubRelease.psm1`; rewrites six variables |
| `radare2/README.md` | Package notes: the handover, the architecture choice, the shim division of labour |
| `tests/GitHubRelease.Tests.ps1` | Extended with radare2's three-asset shape |
| `.github/workflows/update-radare2.yml` | Copy of `update-jadx.yml` with the ids changed |

Nothing else is taken from the package being replaced. In particular
`radare2_git.ps1` — its only automation, which pulled AppVeyor artifacts to publish `-git`
snapshot versions against a 2017 toolchain — is **not** carried over. Task 3's `update.ps1`
replaces its purpose for stable releases, and this repository has no interest in publishing
prereleases. Task 1 copies the description out of the old nuspec and nothing else.

## Deviation from the spec

The spec says the 7,170-character `description` is carried over unchanged. One line of it is false and gets removed:

```
Next release will be 5.5.0, current git is 5.4.3 and the [![latest packaged version(s)]...
```

Written in 2021, when 5.4.2 was current. Upstream is now at 6.2.0, so the sentence is not merely dated but wrong, and a package description is user-facing copy. Everything else — the plugin tables, the architecture list, the 21 Repology badges — is kept exactly as it is, so the diff against the old package stays reviewable.

---

### Task 1: The nuspec

**Files:**
- Create: `radare2/radare2.nuspec`

**Interfaces:**
- Consumes: nothing
- Produces: a nuspec at version 6.2.0 that `choco pack` accepts, with `id` `radare2`

- [ ] **Step 1: Fetch the existing nuspec and extract its description**

```bash
mkdir -p radare2/tools
curl -sL "https://raw.githubusercontent.com/GustavoLCR/Chocolatey-Packages/master/radare2/radare2.nuspec" -o /tmp/r2-orig.nuspec
python3 - <<'EOF'
import xml.dom.minidom as md
d = md.parse('/tmp/r2-orig.nuspec')
meta = d.getElementsByTagName('metadata')[0]
desc = [n for n in meta.childNodes if n.nodeType == 1 and n.tagName == 'description'][0]
text = desc.firstChild.data
print('lines:', len(text.splitlines()), 'chars:', len(text))
open('/tmp/r2-desc.md', 'w').write(text)
EOF
head -6 /tmp/r2-desc.md
```

Expected: `lines: 103 chars: 7170`, and line 4 of the output is the `Next release will be 5.5.0` sentence.

This is the only thing taken from the old package. Do not copy `radare2_git.ps1`, and do not
copy its `tools/` scripts — Task 2 writes those from scratch, because the architecture
selection changes.

- [ ] **Step 2: Drop the stale line**

```bash
python3 - <<'EOF'
lines = open('/tmp/r2-desc.md').read().splitlines(True)
kept = [l for l in lines if not l.startswith('Next release will be')]
assert len(kept) == len(lines) - 1, f'expected to drop exactly 1 line, dropped {len(lines)-len(kept)}'
open('/tmp/r2-desc.md', 'w').writelines(kept)
print('remaining lines:', len(kept))
EOF
```

Expected: `remaining lines: 102`. The assertion is the point — if the sentence ever gets reworded upstream, this fails loudly rather than silently keeping it.

- [ ] **Step 3: Build the nuspec around it**

```bash
python3 - <<'EOF'
desc = open('/tmp/r2-desc.md').read().rstrip()

nuspec = '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2015/06/nuspec.xsd">
  <metadata>
    <id>radare2</id>
    <version>6.2.0</version>
    <packageSourceUrl>https://github.com/moscowmule2240/chocolatey-packages/tree/main/radare2</packageSourceUrl>
    <owners>moscowmule2240</owners>

    <title>radare2</title>
    <authors>radare org</authors>
    <projectUrl>https://rada.re</projectUrl>
    <iconUrl>https://cdn.jsdelivr.net/gh/radareorg/radare.org/img/r2.svg</iconUrl>
    <copyright>2009-2026 radare2 radare org</copyright>
    <licenseUrl>https://www.gnu.org/licenses/lgpl-3.0.html</licenseUrl>
    <requireLicenseAcceptance>true</requireLicenseAcceptance>
    <projectSourceUrl>https://github.com/radareorg/radare2</projectSourceUrl>
    <docsUrl>https://book.rada.re/</docsUrl>
    <bugTrackerUrl>https://github.com/radareorg/radare2/issues</bugTrackerUrl>
    <tags>radare2 analysis debugger decompiler disassembler forensics security reverse-engineering foss</tags>
    <summary>radare2 is a scriptable set of tools and libraries for reverse engineering and forensics.</summary>
    <description><![CDATA[
''' + desc + '''
]]></description>
    <releaseNotes>https://github.com/radareorg/radare2/releases</releaseNotes>
  </metadata>
  <files>
    <file src="tools\\**" target="tools" />
  </files>
</package>
'''
open('radare2/radare2.nuspec', 'w').write(nuspec)
EOF
```

Note the doubled backslash in `tools\\**` — it is a Python string literal, and the file must contain a single backslash.

- [ ] **Step 4: Verify it parses and carries the right fields**

```bash
python3 - <<'EOF'
import xml.dom.minidom as md
d = md.parse('radare2/radare2.nuspec')
meta = d.getElementsByTagName('metadata')[0]
got = {n.tagName: (n.firstChild.data if n.firstChild else '') for n in meta.childNodes if n.nodeType == 1}

assert got['id'] == 'radare2', got['id']
assert got['version'] == '6.2.0', got['version']
assert got['requireLicenseAcceptance'] == 'true'
assert 'lgpl-3.0' in got['licenseUrl']
assert 'dependencies' not in got, 'radare2 needs no runtime dependency'
assert 'raw.githubusercontent.com' not in got['iconUrl'], 'CPMR0076'
assert got['releaseNotes'].startswith('https://'), 'releaseNotes must be a URL, not an inline changelog'
assert 'Next release will be' not in got['description'], 'stale line survived'
assert 'Packaging Status' in got['description'], 'description was truncated'
assert got['projectUrl'] != got['projectSourceUrl'], 'CPMR0041'
print('nuspec OK, description', len(got['description']), 'chars')
EOF
curl -s -o /dev/null -w "  iconUrl -> HTTP %{http_code}\n" "https://cdn.jsdelivr.net/gh/radareorg/radare.org/img/r2.svg"
```

Expected: `nuspec OK, description ~7100 chars` and `iconUrl -> HTTP 200`.

- [ ] **Step 5: Commit**

```bash
git add radare2/radare2.nuspec
git commit -m "feat: add the radare2 nuspec at 6.2.0

Metadata is carried over from the package being taken over, so the diff against
what users see today stays reviewable: title, authors, urls, tags, summary and
the description are unchanged. projectSourceUrl is kept because it genuinely
differs from projectUrl, and the icon still points at the upstream CDN copy
because radareorg/radare.org carries no license file.

Three fields change. The copyright year had stopped at 2021, releaseNotes held
the 5.4.2 changelog inline where a URL never goes stale, and one sentence of the
description announced 5.5.0 as the next release."
```

---

### Task 2: The install and uninstall scripts

**Files:**
- Create: `radare2/tools/chocolateyinstall.ps1`
- Create: `radare2/tools/chocolateyuninstall.ps1`

**Interfaces:**
- Consumes: nothing
- Produces: `$url32` / `$checksum32` / `$url64` / `$checksum64` / `$urlArm64` / `$checksumArm64` assignment lines, which Task 3's `au_SearchReplace` rewrites

- [ ] **Step 1: Write the install script**

Runs under Windows PowerShell 5.1.

```powershell
$ErrorActionPreference = 'Stop'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Rewritten by ../update.ps1 on every release. The checksums come from the GitHub
# release assets' digest field, so they are the hashes GitHub itself records.
$url32         = 'https://github.com/radareorg/radare2/releases/download/6.2.0/radare2-6.2.0-w32.zip'
$checksum32    = 'b06959f8221db6154e4d79051300585c86e9560942219b9e19d53a5114937b44'
$url64         = 'https://github.com/radareorg/radare2/releases/download/6.2.0/radare2-6.2.0-w64.zip'
$checksum64    = 'adb1ffd158066ea41316fa33b6d23b362aa9258df800721f7d15a42eefdd9202'
$urlArm64      = 'https://github.com/radareorg/radare2/releases/download/6.2.0/radare2-6.2.0-w64-arm64.zip'
$checksumArm64 = 'a5a956b8d9c3e0ff0290584215dcb85bc973866ade5d8247b9df9723c1fdebcf'

# Upstream ships three Windows archives. Install-ChocolateyZipPackage takes a
# 32-bit and a 64-bit url, which cannot express the third, so the archive is
# chosen here and handed over as a single pair.
#
# --x86 is honoured first: a helper given both urls would apply it for us, but a
# script that picks the url itself has to check chocolateyForceX86 itself.
# arm64 is tested before x64 because Windows on ARM also reports
# Is64BitOperatingSystem = $true.
$isArm64 = ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') -or ($env:PROCESSOR_ARCHITEW6432 -eq 'ARM64')

if ($env:chocolateyForceX86) {
    $url = $url32;    $checksum = $checksum32
} elseif ($isArm64) {
    $url = $urlArm64; $checksum = $checksumArm64
} elseif ([Environment]::Is64BitOperatingSystem) {
    $url = $url64;    $checksum = $checksum64
} else {
    $url = $url32;    $checksum = $checksum32
}

Install-ChocolateyZipPackage `
    -PackageName   $env:ChocolateyPackageName `
    -Url           $url `
    -Checksum      $checksum `
    -ChecksumType  'sha256' `
    -UnzipLocation $toolsDir

# The archive expands to radare2-<version>-<arch>/, a name that changes with every
# release and differs per architecture, so bin/ is located rather than rebuilt.
$binPath = Get-ChildItem -Path $toolsDir -Directory -Recurse -Filter 'bin' |
           Where-Object { Test-Path (Join-Path $_.FullName 'radare2.exe') } |
           Select-Object -First 1 -ExpandProperty FullName
if (-not $binPath) { throw "Could not find bin\radare2.exe under $toolsDir after unpacking." }

# Chocolatey shims every .exe in the package folder by itself, which covers all
# sixteen tools in bin/. Only the r2 alias needs registering: no executable
# carries that name, and the package being taken over provides it, so anyone
# upgrading would lose the command they actually type.
Install-BinFile -Name 'r2' -Path (Join-Path $binPath 'radare2.exe')
```

- [ ] **Step 2: Write the uninstall script**

```powershell
$ErrorActionPreference = 'Stop'

# Automatic shims go when Chocolatey removes the package folder. The r2 alias was
# registered explicitly, so it has to be removed explicitly or the command lingers.
Uninstall-BinFile -Name 'r2'
```

- [ ] **Step 3: Verify the six patterns hit exactly one line each and leave the branch alone**

```bash
python3 - <<'EOF'
import re
patterns = {
    'url32':         r"(?i)(\$url32\s*=\s*)'[^']*'",
    'checksum32':    r"(?i)(\$checksum32\s*=\s*)'[^']*'",
    'url64':         r"(?i)(\$url64\s*=\s*)'[^']*'",
    'checksum64':    r"(?i)(\$checksum64\s*=\s*)'[^']*'",
    'urlArm64':      r"(?i)(\$urlArm64\s*=\s*)'[^']*'",
    'checksumArm64': r"(?i)(\$checksumArm64\s*=\s*)'[^']*'",
}
src = open('radare2/tools/chocolateyinstall.ps1').read()

ok = True
for name, p in patterns.items():
    n = len(re.findall(p, src))
    if n != 1:
        ok = False
    print(f"  {'OK ' if n == 1 else 'NG '} {name:14s} matches {n} (expected 1)")

replaced = src
for name, p in patterns.items():
    replaced = re.sub(p, lambda m, n=name: m.group(1) + f"'NEW-{n}'", replaced)

changed = [b for a, b in zip(src.splitlines(), replaced.splitlines()) if a != b]
print(f"  changed lines: {len(changed)} (expected 6)")
for c in changed:
    print("     ", c.strip()[:70])

for line in replaced.splitlines():
    if 'isArm64' in line or 'chocolateyForceX86' in line or '$url = $url' in line:
        print("  preserved:", line.strip()[:72])

assert ok and len(changed) == 6
print("  => OK")
EOF
```

Expected: six `OK` lines, `changed lines: 6`, and the `if/elseif/else` selection lines listed as preserved. The `$url = $url64` style assignments inside the branch must NOT be rewritten — they have no quoted literal, which is why every pattern requires `'...'`.

- [ ] **Step 4: Check CPMR0010 and brace balance**

```bash
if grep -rnE 'cinst|choco (install|upgrade)' radare2/; then
  echo "CPMR0010: FOUND - rewrite the text above"
else
  echo "CPMR0010: clean"
fi
python3 - <<'EOF'
import glob, re
for f in sorted(glob.glob('radare2/tools/*.ps1')):
    src = re.sub(r'(?m)#.*$', '', re.sub(r'<#.*?#>', '', open(f).read(), flags=re.S))
    b, p, q = src.count('{') - src.count('}'), src.count('(') - src.count(')'), src.count("'") % 2
    print(f"  {'OK ' if b == p == q == 0 else 'NG '} {f}  braces={b:+d} parens={p:+d} quotes={'even' if q == 0 else 'ODD'}")
EOF
```

Expected: `CPMR0010: clean` and two `OK` lines.

- [ ] **Step 5: Commit**

```bash
git add radare2/tools/
git commit -m "feat: add the radare2 install and uninstall scripts

Upstream ships w32, w64 and w64-arm64; Install-ChocolateyZipPackage takes only a
32-bit and a 64-bit url, so the archive is selected in the script and passed as
one pair. That means chocolateyForceX86 has to be honoured explicitly - the
helper would have done it for free - and losing it would regress the previous
maintainer's last change to this package, which was a --forcex86 fix. arm64 is
tested before x64 because Windows on ARM also reports Is64BitOperatingSystem.

Only the r2 alias is registered. Chocolatey shims every .exe in the package
folder on its own, which covers all sixteen tools under bin/, and removes them
with the package; r2 matches no executable name, so it is registered and
unregistered by hand."
```

---

### Task 3: The AU script and its test

**Files:**
- Create: `radare2/update.ps1`
- Modify: `tests/GitHubRelease.Tests.ps1`

**Interfaces:**
- Consumes: `Get-GitHubLatestRelease -Repo <string>`, `Get-ReleaseVersion -Release <object>`, `Select-ReleaseAsset -Release <object> -Name <string>`, `Get-AssetChecksum -Asset <object>` from `scripts/GitHubRelease.psm1`
- Produces: nothing consumed by later tasks

- [ ] **Step 1: Add the failing test**

Append to `tests/GitHubRelease.Tests.ps1`:

```powershell
Describe 'GitHubRelease against a radare2-shaped release' {
    BeforeAll {
        $script:r2 = [pscustomobject]@{
            tag_name = '6.2.0'
            assets   = @(
                [pscustomobject]@{
                    name   = 'radare2-6.2.0-w64.zip'
                    digest = 'sha256:adb1ffd158066ea41316fa33b6d23b362aa9258df800721f7d15a42eefdd9202'
                    browser_download_url = 'https://github.com/radareorg/radare2/releases/download/6.2.0/radare2-6.2.0-w64.zip'
                },
                [pscustomobject]@{
                    name   = 'radare2-6.2.0-w32.zip'
                    digest = 'sha256:b06959f8221db6154e4d79051300585c86e9560942219b9e19d53a5114937b44'
                    browser_download_url = 'https://github.com/radareorg/radare2/releases/download/6.2.0/radare2-6.2.0-w32.zip'
                },
                [pscustomobject]@{
                    name   = 'radare2-6.2.0-w64-arm64.zip'
                    digest = 'sha256:a5a956b8d9c3e0ff0290584215dcb85bc973866ade5d8247b9df9723c1fdebcf'
                    browser_download_url = 'https://github.com/radareorg/radare2/releases/download/6.2.0/radare2-6.2.0-w64-arm64.zip'
                },
                [pscustomobject]@{
                    name   = 'radare2-6.2.0-android-sdk.zip'
                    digest = 'sha256:0000000000000000000000000000000000000000000000000000000000000000'
                    browser_download_url = 'https://github.com/radareorg/radare2/releases/download/6.2.0/radare2-6.2.0-android-sdk.zip'
                }
            )
        }
    }

    It 'reads a version from a tag with no v prefix' {
        Get-ReleaseVersion -Release $script:r2 | Should -Be '6.2.0'
    }

    It 'selects each of the three Windows archives' {
        (Select-ReleaseAsset -Release $script:r2 -Name 'radare2-6.2.0-w64.zip').browser_download_url       | Should -BeLike '*-w64.zip'
        (Select-ReleaseAsset -Release $script:r2 -Name 'radare2-6.2.0-w32.zip').browser_download_url       | Should -BeLike '*-w32.zip'
        (Select-ReleaseAsset -Release $script:r2 -Name 'radare2-6.2.0-w64-arm64.zip').browser_download_url | Should -BeLike '*-w64-arm64.zip'
    }

    It 'does not confuse the w64 archive with the w64-arm64 one' {
        $w64 = Select-ReleaseAsset -Release $script:r2 -Name 'radare2-6.2.0-w64.zip'
        $w64.name | Should -Not -BeLike '*arm64*'
    }

    It 'ignores the non-Windows assets in the same release' {
        { Select-ReleaseAsset -Release $script:r2 -Name 'radare2-6.2.0-w64' } |
            Should -Throw -ExpectedMessage '*found 0*'
    }

    It 'reads the checksum of each architecture from its digest' {
        $w32 = Select-ReleaseAsset -Release $script:r2 -Name 'radare2-6.2.0-w32.zip'
        Get-AssetChecksum -Asset $w32 |
            Should -Be 'b06959f8221db6154e4d79051300585c86e9560942219b9e19d53a5114937b44'
    }
}
```

`radare2-6.2.0-android-sdk.zip` is in the fixture on purpose: the real release carries it, and it is the asset a loose match would most plausibly pick up.

- [ ] **Step 2: Note that the test cannot be run here**

There is no `pwsh` on this machine. Record that the five new cases are unverified until the `Tests` workflow runs on `windows-latest`, and do not describe them as passing.

- [ ] **Step 3: Write the AU script**

```powershell
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
```

`Get-DualArchSearchReplace` is deliberately not used: it is fixed at the four-variable `url64`/`checksum64`/`urlArm64`/`checksumArm64` shape, and this package has six.

- [ ] **Step 4: Confirm the live API still matches what the script expects**

```bash
python3 - <<'EOF'
import json, re, urllib.request
req = urllib.request.Request('https://api.github.com/repos/radareorg/radare2/releases/latest',
                             headers={'User-Agent': 'Mozilla/5.0', 'Accept': 'application/vnd.github+json'})
rel = json.load(urllib.request.urlopen(req))

m = re.match(r'^v?(\d+\.\d+(?:\.\d+)?)$', rel['tag_name'])
assert m, f"tag {rel['tag_name']!r} would not parse"
v = m.group(1)
print(f"  tag {rel['tag_name']!r} -> version {v}")

for suffix in ('w32', 'w64', 'w64-arm64'):
    name = f'radare2-{v}-{suffix}.zip'
    hits = [a for a in rel['assets'] if a['name'] == name]
    assert len(hits) == 1, f'{name}: {len(hits)} matches'
    digest = re.match(r'^sha256:([0-9a-f]{64})$', hits[0].get('digest', ''))
    assert digest, f"{name}: unreadable digest {hits[0].get('digest')!r}"
    print(f"  {name:30s} -> {digest.group(1)[:16]}...")
EOF
```

Expected: the tag resolves to `6.2.0` and all three archives match exactly once with a readable digest. A failure here means upstream renamed an asset and `au_GetLatest` needs its names updated before anything else.

- [ ] **Step 5: Commit**

```bash
git add radare2/update.ps1 tests/GitHubRelease.Tests.ps1
git commit -m "feat: drive the radare2 package from the GitHub releases adapter

Resolves all three Windows archives by exact name and takes each checksum from
its asset digest, so a version bump costs one API call rather than 36 MB of
downloads. Exact names matter here more than for jadx: the same release also
ships r2blob, wasi, ios-sdk and android-sdk archives.

au_SearchReplace is written inline because it rewrites six variables;
Get-DualArchSearchReplace is fixed at the four-variable shape the other packages
share. The tests gain a radare2-shaped fixture, including the android-sdk asset,
which is what a loose match would most plausibly pick up.

Not run here - this machine has no pwsh. The five new cases are unverified until
the Tests workflow runs them on windows-latest."
```

---

### Task 4: README and workflow

**Files:**
- Create: `radare2/README.md`
- Create: `.github/workflows/update-radare2.yml`
- Modify: `README.md` (the package table)

**Interfaces:**
- Consumes: `radare2/update.ps1` from Task 3, `scripts/Check-ChocolateyStatus.ps1` (existing)
- Produces: nothing consumed by later tasks

- [ ] **Step 1: Write the package README**

```markdown
# radare2

[radare2](https://rada.re) — a scriptable set of tools and libraries for reverse
engineering and forensics.

## Upstream

Releases: <https://github.com/radareorg/radare2/releases>

The package installs the official per-architecture archive:
`radare2-<version>-w64.zip`, `-w32.zip`, or `-w64-arm64.zip`. The same release
also carries `r2blob`, `wasi`, `ios-sdk` and `android-sdk` archives, so
`update.ps1` matches asset names exactly rather than by prefix.

## Architectures

Three, where the package this was taken over from covered two and Scoop still
covers two. Upstream builds `w64-arm64` and no Windows package manager was
shipping it, so a Windows-on-ARM machine had no packaged radare2 at all.

`Install-ChocolateyZipPackage` accepts one 32-bit and one 64-bit URL and cannot
express a third, so the install script selects the archive itself. Two
consequences worth remembering before editing that block:

- **`$env:chocolateyForceX86` must be checked by hand.** The helper honours
  `--x86` for free only when it is handed both URLs. The last change the previous
  maintainer made to this package was a `--forcex86` fix; dropping the check
  would put that bug straight back.
- **arm64 is tested before x64.** Windows on ARM also reports
  `Is64BitOperatingSystem = $true`, so the reverse order hands it the x64 build.

## Shims

The archive carries sixteen executables, all under `bin/`:

```
r2agent  r2pm  r2r  rabin2  radare2  radiff2  rafind2  rafs2
ragg2    rahash2  rapatch2  rarun2  rasign2  rasm2  ravc2  rax2
```

None of them are registered explicitly. Chocolatey shims every `.exe` in the
package folder by itself and removes those shims with the package — packages that
do not want this opt out per file, which is what `ghidra` does with `.ignore`
files. Enumerating them here would re-implement that mechanism and add an
uninstall loop that has to stay in agreement with it.

`r2` is the exception: no executable carries that name, it is how the tool is
invariably invoked, and the package being taken over provides it. It is therefore
registered with `Install-BinFile` and, because explicit shims are not cleaned up
automatically, removed with `Uninstall-BinFile`.

Scoop takes the other approach — a hand-written `bin` list — and it has drifted
four binaries behind the archive it installs: `r2pm`, `r2r`, `rafs2` and
`rapatch2` are missing there. `r2pm` is radare2's own plugin manager.

## History

The `radare2` id was previously maintained by
[GustavoLCR](https://github.com/GustavoLCR/Chocolatey-Packages). Chocolatey served
5.4.2, approved 2021-09-26, while upstream reached 6.2.0; nothing between the two
was ever submitted. The package source contains no updater for stable releases —
only a script that pulled AppVeyor artifacts to publish `-git` snapshots, pinned
to a 2017 toolchain — so every stable release was published by hand until that
stopped. Maintenance was transferred following the Chocolatey Package Triage
Process.

## Maintenance notes

- Checksums come from each release asset's `digest` field, so a version bump
  needs no download. `Get-RemoteChecksum` is only the fallback for a release that
  publishes no digest.
- The archive expands to `radare2-<version>-<arch>/`, so the install script
  searches for `bin/radare2.exe` rather than assuming a path — the directory name
  changes with every release and differs per architecture.
- The icon points at the upstream CDN copy rather than a file in this repository:
  `radareorg/radare.org` carries no license file, so redistributing the logo would
  be on unclear terms.
- CPMR0010 is a plain string match: never write a Chocolatey install command in
  these scripts, not even inside a comment.
- The CI `Test install / uninstall` step only runs when AU produced a `.nupkg`,
  so a package whose nuspec already matches upstream gets no install coverage
  from CI — test it on a real Windows machine.
- When re-testing after a fix, run `choco pack` again. `choco install -s .`
  installs from the `.nupkg` in the directory, not from the working tree.
```

- [ ] **Step 2: Create the workflow from the jadx one**

```bash
cp .github/workflows/update-jadx.yml .github/workflows/update-radare2.yml
python3 - <<'EOF'
p = '.github/workflows/update-radare2.yml'
s = open(p, encoding='utf-8').read()

reps = [
    ('name: Update jadx',      'name: Update radare2'),
    ('  group: update-jadx',   '  group: update-radare2'),
    ('      PKG_DIR: jadx',    '      PKG_DIR: radare2'),
    ('''  # Disabled until the maintainer handover for the existing jadx package
  # completes. The id is currently held by another maintainer, so a scheduled
  # run would build packages this repository cannot push. See
  # docs/superpowers/specs/2026-08-22-au-shared-modules-design.md.''',
     '''  # Disabled until the maintainer handover for the existing radare2 package
  # completes. The id is currently held by another maintainer, so a scheduled
  # run would build packages this repository cannot push. See
  # docs/superpowers/specs/2026-08-23-radare2-package-design.md.'''),
]
missing = [a.splitlines()[0] for a, _ in reps if a not in s]
for a, b in reps:
    s = s.replace(a, b)
open(p, 'w', encoding='utf-8').write(s)
print('unmatched:', missing if missing else 'none (4/4 replaced)')
EOF
```

- [ ] **Step 3: Add radare2 to the repository README table**

```bash
python3 - <<'EOF'
p = 'README.md'
s = open(p, encoding='utf-8').read()
old = "| [`typeless`](typeless/) | Typeless — AI voice dictation for Windows | [package README](typeless/README.md) |"
new = ("| [`radare2`](radare2/) | radare2 — reverse engineering framework and toolset | [package README](radare2/README.md) |\n"
       + old)
assert old in s and 'radare2' not in s
open(p, 'w', encoding='utf-8').write(s.replace(old, new))
print('README table updated')
EOF
sed -n '/^## Packages/,/^$/p' README.md
```

Expected: four rows, alphabetical — `antigravity-ide`, `jadx`, `radare2`, `typeless`.

- [ ] **Step 4: Verify the workflow parses and carries no jadx leftovers**

```bash
python3 - <<'EOF'
import yaml
d = yaml.safe_load(open('.github/workflows/update-radare2.yml'))
job = list(d['jobs'].values())[0]
trig = d.get(True) or d.get('on')

assert d['name'] == 'Update radare2', d['name']
assert job['env']['PKG_DIR'] == 'radare2', job['env']['PKG_DIR']
assert d['concurrency']['group'] == 'update-radare2', d['concurrency']['group']
assert 'schedule' not in trig, 'the schedule must stay disabled until the handover completes'
assert 'workflow_dispatch' in trig
au = [s for s in job['steps'] if s['name'].startswith('Run AU')][0]
assert 'GITHUB_TOKEN' in au.get('env', {}), 'the AU step needs GITHUB_TOKEN'
print('workflow OK:', d['name'], '/ steps:', len(job['steps']))
EOF
grep -n 'jadx' .github/workflows/update-radare2.yml || echo "  no jadx leftovers"
python3 -c "
import yaml, glob
for f in sorted(glob.glob('.github/workflows/*.yml')):
    d = yaml.safe_load(open(f))
    g = d.get('concurrency', {}).get('group')
    print(f'  {f.split(\"/\")[-1]:28s} group={g}')
"
```

Expected: `workflow OK: Update radare2 / steps: 9`, no `jadx` matches, and four distinct concurrency groups. If `pyyaml` is missing, create a virtualenv for it — do not `pip install --user` into the shared interpreter.

- [ ] **Step 5: Commit**

```bash
git add radare2/README.md .github/workflows/update-radare2.yml README.md
git commit -m "ci: add the radare2 update workflow and package notes

Mirrors the other packages. The schedule stays commented out until the handover
completes, and the concurrency group is update-radare2 rather than the
update-jadx it was copied from - leaving that would have made the two workflows
cancel each other.

The package README records the two things that are easy to break when editing
the architecture block: chocolateyForceX86 has to be checked by hand once the
script picks its own URL, and arm64 must be tested before x64."
```

---

## Verification after all tasks

- [ ] `git status --porcelain` is empty; no `.nupkg` anywhere.
- [ ] Every workflow YAML and every nuspec parses; four distinct concurrency groups.
- [ ] The six replacement patterns still match exactly one line each.
- [ ] `grep -rnE 'cinst|choco (install|upgrade)' radare2/` finds nothing.
- [ ] Push, and confirm the `Tests` workflow is green on `windows-latest` — this is the first time the new Pester cases run at all.
- [ ] **Then** verify on Windows, per the spec's table: install on x64, `r2 -v` reports 6.2.0, `Get-Command r2, rabin2, rasm2, rax2, r2pm` all resolve, 17 shims exist, and `choco uninstall radare2 -y` removes every one of them.
- [ ] Do **not** enable the schedule, and do **not** push anything to Chocolatey.

## Follow-up, once Windows verification passes

Not part of this plan — recorded so the sequence is not lost:

1. Open a GitHub issue on `GustavoLCR/Chocolatey-Packages` describing the gap, and send the Contact Maintainers message from the radare2 package page. Record both dates.
2. Wait seven days. If there is no reply, contact the Site Admins.
3. Once maintainer access is granted, **push 6.2.0 by hand** — `choco pack` then `choco push` from the Windows machine. Uncommenting `schedule:` is not enough: AU only acts on versions newer than the nuspec, so with the nuspec at 6.2.0 and upstream at 6.2.0 a scheduled run no-ops forever.
4. Then uncomment `schedule:`, which takes over from 6.2.2 onwards, and watch the first run that finds a new version through to a push.

This is deliberately after verification, unlike the jadx handover, where the issue went out before the package had ever been installed and the first Windows test then found a bug.

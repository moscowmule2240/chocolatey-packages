# Design: shared AU update modules and the jadx package

- Created: 2026-08-22
- Status: Design (not implemented)

## Context

### The duplication that exists today

The two packages in this repository each carry a self-contained `update.ps1`. Stripped of
comments and blank lines they are 96 lines (`antigravity-ide`) and 126 lines (`typeless`), and
**51 of those lines are byte-identical**.

The largest offender is `Get-ValidatedContent`, the retrying fetch helper: 35 lines against 36,
with exactly one meaningful difference.

```diff
-  $content = [string]$response.Content
+  $raw     = $response.Content
+  $content = if ($raw -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($raw) } else { [string]$raw }
```

The `typeless` variant is a strict superset: when the response is not a `byte[]` it falls through
to `[string]$raw`, which is what `antigravity-ide` does unconditionally. One copy serves both.

`au_SearchReplace` is identical in both packages, as is the closing
`Update-Package -ChecksumFor none -NoReadme`. The preamble (`Import-Module AU`,
`$ErrorActionPreference`, `Set-Location $PSScriptRoot`, `$Headers`, `$RetryDelaysSeconds`) is
identical apart from whitespace.

Only `au_GetLatest` is genuinely package-specific.

### Why jadx is being added now

`jadx` already exists on the Chocolatey Community Repository, maintained by FranklinYu, with 25
approved versions. Its last two releases never reached approval:

| Version | Submitted | Verification failed | Stale notice | Closed |
| --- | --- | --- | --- | --- |
| 1.5.3 | 2025-09-09 | 2025-09-09 | 2025-09-29 | 2025-10-14 |
| 1.5.6 | 2026-07-11 | 2026-07-11 | 2026-07-31 | 2026-08-15 |

Both were closed automatically by `chocolatey-ops` after the verification failure went unanswered
for the full 35-day grace period. No human reviewer commented on either version.

A maintainer handover is in progress under the Chocolatey Package Triage Process: issue
[#23](https://github.com/FranklinYu/chocolatey-packages/issues/23) was opened on 2026-08-22 and the
Contact Maintainers form was sent the same day. The seven-day response window ends on 2026-08-29.

**This design assumes the handover succeeds. Nothing in the `jadx/` folder is published until
maintainer access is granted.**

## Findings

Each of these was verified against a primary source before the design was settled.

### 1. The verification failures are caused by the Java dependency, not by jadx

The test log for 1.5.6
([gist](https://gist.github.com/choco-bot/14915e11926b1c65840bc0f3f0845395)) ends:

```
05:35:05  Elevating permissions and running ["...\JRE8x64.exe" /s  REBOOT=0 SPONSORS=0 AUTO_UPDATE=0]
06:17:25  [WARN ] Chocolatey timed out waiting for the command to finish.
          The timeout specified (or the default value) was '2700' seconds.
06:17:27  [ERROR] The install of jre8 was NOT successful.
06:17:29  [ERROR] Failed to install javaruntime because a previous dependency failed.
06:17:29  [ERROR] Failed to install jadx because a previous dependency failed.
          Chocolatey installed 0/3 packages. 3 packages failed.
```

The Oracle JRE 8 installer hangs during its silent install and hits the execution timeout. `jre8`
fails, `javaruntime` fails with it, and jadx is never installed. The log for 1.5.3
([gist](https://gist.github.com/choco-bot/2274ee3af4e62c962e0682d08fe9a699)) shows the same
sequence.

The dependency is declared as:

```xml
<dependency id="javaruntime" version="[8,9)" />
```

`javaruntime` describes itself as "just a metapackage for the latest JRE (currenly JRE 8)" and
depends on `jre8`. Upstream jadx requires Java 11 or later, so the dependency does not match the
runtime the software needs, and it ties every verification run to the reliability of the Oracle
JRE 8 installer.

### 2. Chocolatey cannot express "any Java 11 or later"

Dependency resolution matches on package id. `temurin11`, `temurin17` and `temurin21` are separate
ids with no dependencies between them, so a machine running `temurin21` still receives `temurin11`
if a package depends on it.

The Chocolatey FAQ is explicit that the feature which would solve this does not exist yet:

> Chocolatey has the concept of virtual packages (coming, please see GitHub Issue) and meta
> packages. [...] So in the case of git, git.install, and git.commandline — git is that virtual
> package (currently it is really just a metapackage until the virtual packages feature is
> complete).

No Java 11+ metapackage exists on the repository. Declaring any Java dependency therefore pins
users to one specific JDK id, and jadx's audience — Java developers and Android reverse
engineers — will overwhelmingly already have a JDK installed.

Installing a JDK from the install script instead is not an option: CPMR0010 (*Script Contains
Choco Commands*) is a **Requirement**, and its detection is a plain string match on `cinst`,
`choco install` and `choco upgrade` — comments count.

### 3. Java tools on the repository do not declare a Java dependency

| Package | Java dependency | Java required by the software |
| --- | --- | --- |
| `ghidra` 12.1.3 | none | 17+ |
| `zap` | none | 11+ |
| `jenkins` | none | 17+ |
| `openrefine` | none | 11+ |
| `visualvm` | none | 8+ |
| `dbeaver` | `chocolatey-core.extension` only | bundled |
| `jadx` 1.5.5 | `javaruntime [8.0, 9.0)` | 11+ |
| `apktool` | `javaruntime 1.8.0` | |
| `jmeter` | `javaruntime 8.0.431` | |

Every package that declares a Java dependency declares `javaruntime`, which is Java 8. Every tool
that requires Java 11 or later declares nothing. That is not an oversight — it is the only
available option, given finding 2.

`ghidra` is the closest precedent: same problem domain, Java 17+, no dependency, no Java detection
at all, and its 12.1.3 was approved on 2026-08-19.

### 4. Upstream and other distributions agree on the artifact

The jadx README documents unpacking the release zip and running `bin/jadx` (CLI) or `bin/jadx-gui`
(GUI), and states that Java 11+ 64-bit must be installed separately. Its Install section lists
Arch, Homebrew and Flathub only — no Windows package manager.

Scoop (Extras) uses `jadx-<version>.zip`, shims both `bin\jadx.bat` and `bin\jadx-gui.bat`, and
declares `"suggest": {"JDK": "java/openjdk"}` — a suggestion, not a dependency. Homebrew builds
from source and depends on `openjdk`. None of the distributions checked (Scoop, Homebrew, the
existing Chocolatey package) ships the `-with-jre-win` asset.

### 5. The existing install script has a second, quieter bug

```powershell
Start-Process -FilePath 'java.exe' -RedirectStandardError $tempFile -ArgumentList '-version' -NoNewWindow -Wait
if (! (Select-String -Path $tempFile -Pattern 64-Bit)) { throw 'require 64-bit Java' }
```

It checks the bit width but never the version. A machine with only Java 8 passes this check and
then fails at runtime, because jadx needs 11+. The declared dependency installs exactly that
Java 8.

### 6. `projectSourceUrl` duplicates `projectUrl`

The 1.5.6 validation flagged CPMR0041 as a Guideline: `projectUrl` and `projectSourceUrl` are both
`https://github.com/skylot/jadx`. A Note (CPMR0060) also fired because the package embeds the
release zip.

## Design

### Module layout

```
scripts/
├── Check-ChocolateyStatus.ps1   # unchanged
├── ChocoUpdate.psm1             # new — transport and shared AU boilerplate
└── GitHubRelease.psm1           # new — GitHub Releases as an update source
```

PowerShell classes are a poor fit here: AU discovers `au_GetLatest`, `au_BeforeUpdate` and
`au_SearchReplace` by name in the global scope, so a class would only add a layer that each
package has to unwrap. Modules export functions directly into that model.

Each `update.ps1` keeps its own `au_*` definitions and imports the modules:

```powershell
Set-Location -Path $PSScriptRoot
Import-Module "$PSScriptRoot/../scripts/ChocoUpdate.psm1" -Force
```

`$PSScriptRoot` resolves regardless of the caller's working directory, so this holds under CI,
which invokes `& "./$env:PKG_DIR/update.ps1"` from the repository root.

One scope subtlety makes the whole migration work: AU invokes the `au_*` functions in the global
scope — that is why the inline helpers today carry the `global:` prefix. `Import-Module` called
from a script imports into the global session state, so module exports are resolvable from inside
`global:au_GetLatest` without any prefix. Passing `-Scope Local` would break exactly that; don't.

### `ChocoUpdate.psm1`

Exports:

- **`Get-ValidatedContent -Uri -Validate -What [-Headers]`** — the `typeless` implementation
  verbatim, including the `byte[]` decode and the diagnostic throw that reports status, body
  length and the trailing 200 characters. Retry delays stay at 5/15/30 seconds. `-Headers`
  defaults to the module's User-Agent; `GitHubRelease.psm1` passes `Accept` and `Authorization`
  through it. This helper found two real bugs
  by reporting the response tail; that behaviour is load-bearing and must not be trimmed.
- **`Get-DualArchSearchReplace`** — returns the `au_SearchReplace` hashtable for the
  `$url64`/`$checksum64`/`$urlArm64`/`$checksumArm64` shape that both existing packages use.

Module-scope defaults (`$Headers`, `$RetryDelaysSeconds`) move here. Packages that need a
different User-Agent pass one explicitly rather than mutating module state.

### `GitHubRelease.psm1`

Exports:

- **`Get-GitHubLatestRelease -Repo`** — fetches `/repos/<repo>/releases/latest`, which already
  excludes drafts and prereleases, and returns the parsed release. Sends
  `Authorization: Bearer $env:GITHUB_TOKEN` when that variable is set. The point of
  authenticating is less the ceiling (1,000 requests/hour/repository for the Actions token; 5,000
  for a PAT) than that the unauthenticated 60/hour is metered per IP address, which shared CI
  runners exhaust. Unauthenticated calls still work for local runs.
- **`Get-ReleaseVersion -Release`** — strips a leading `v` from `tag_name` and returns the
  `x.y.z` string. Throws if the tag does not match, rather than silently producing a wrong
  version.
- **`Select-ReleaseAsset -Release -Name`** — returns the single asset whose `name` matches, and
  throws when zero or more than one match. Ambiguity here would silently ship the wrong artifact.

Release assets carry a `digest` field (`sha256:<hex>`). For `jadx-1.5.6.zip` it equals the
SHA-256 the previous maintainer recorded in VERIFICATION.txt, which independently confirms the
field. Consumers should prefer it over downloading and hashing, falling back to
`Get-RemoteChecksum` only when the field is absent.

`GitHubRelease.psm1` imports `ChocoUpdate.psm1` by `$PSScriptRoot`-relative path and routes its
HTTP through `Get-ValidatedContent`, so GitHub gets the same retry and diagnostic behaviour as
the existing scrapers. A package that uses GitHub imports only `GitHubRelease.psm1` and receives
the transport module transitively.

### Migrating the existing packages

`antigravity-ide` and `typeless` keep their `au_GetLatest` unchanged and drop everything the
modules now own. Expected result: roughly 50 lines removed from each, with no behavioural change.

`antigravity-ide` currently defines `Get-ValidatedContent` without the `byte[]` decode. Adopting
the `typeless` version is a widening, not a change: HTML responses arrive as `[string]` and take
the same path they take today.

This trades away one AU convention: a package folder stops being self-contained, because
`update.ps1` now needs `../scripts`. Accepted — CI always checks out the whole repository, and a
folder copied out on its own fails immediately and loudly at `Import-Module` rather than subtly.

### The jadx package

```
jadx/
├── jadx.nuspec
├── README.md
├── icon.png
├── update.ps1
└── tools/
    ├── chocolateyinstall.ps1
    └── chocolateyuninstall.ps1
```

Decisions, each following from a finding above:

1. **No Java dependency** (findings 2, 3). The nuspec declares no `<dependencies>`. This removes
   the failure mode that closed 1.5.3 and 1.5.6 structurally rather than by swapping one JDK id
   for another, and it stops shipping a redundant JDK to users who already have one.
2. **Java is detected, never enforced** (finding 5). The install script locates `java.exe`, reads
   its version, and emits `Write-Warning` when Java is absent or older than 11. It does not
   `throw`. Unpacking the archive and registering shims do not need Java, so verification passes
   on a machine with no JDK — which is exactly what the verifier provides.
3. **Download at install time, do not embed** (finding 4). `Install-ChocolateyZipPackage` with
   `-Url64bit` and `-Checksum64` (`-ChecksumType64 'sha256'`), as `ghidra` does. This drops the
   nupkg from ~69 MB to a few KB, removes the CPMR0060 Note, and also removes LICENSE.txt and
   VERIFICATION.txt, which are required only when binaries are embedded. The zip is Java bytecode
   and architecture-independent, so the install script carries a single url/checksum pair:
   `Get-DualArchSearchReplace` stays with the two dual-arch packages, and jadx declares its own
   two-line `au_SearchReplace` inline.
4. **The standard archive** (finding 4). `jadx-<version>.zip`, not `-with-jre-win`. Both
   `bin\jadx.bat` and `bin\jadx-gui.bat` are shimmed via `Install-BinFile`, matching Scoop and the
   existing package.
5. **Drop `projectSourceUrl`** (finding 6). `packageSourceUrl` points at this repository;
   `projectUrl` points at upstream. There is no third URL to give.
6. **Uninstall mirrors install**. `chocolateyuninstall.ps1` removes both shims with
   `Uninstall-BinFile` — explicit `Install-BinFile` shims are not cleaned up automatically — and
   deletes the start-menu shortcut.
7. **Icon follows the repo convention**: `jadx/icon.png`, referenced as
   `https://cdn.jsdelivr.net/gh/moscowmule2240/chocolatey-packages@main/jadx/icon.png` like the
   other two packages (jsdelivr also avoids the CPMR0076 raw-GitHub-URL flag).

`update.ps1` uses `GitHubRelease.psm1`: resolve the latest release, take the version from the
tag, select the `jadx-<version>.zip` asset, and take the checksum from the asset's `digest`
field — no download at all, the same property the typeless feed gives us. Only if `digest` is
ever absent does `au_BeforeUpdate` fall back to `Get-RemoteChecksum`, and the ~69 MB download
happens only on that degraded path.

### Workflow

`.github/workflows/update-jadx.yml` mirrors the existing two. `GITHUB_TOKEN` is passed to the AU
step so `Get-GitHubLatestRelease` uses the authenticated rate limit. The `schedule:` block stays
commented out until the handover completes, matching how `typeless` was introduced.

## Rejected alternatives

**Depend on `temurin11`.** The obvious reading of "fix the dependency", and what issue #23
suggests. Rejected because dependency resolution is by id (finding 2): every user already running
`temurin17`, `temurin21`, `zulu` or `openjdk` would receive a second, redundant JDK, and jadx's
audience mostly has one already. It also only moves the failure mode — if `temurin11` breaks the
way `jre8` did, the package is closed again for the same reason.

**Ship the JRE-bundled archive.** `jadx-gui-<version>-with-jre-win.zip` removes the Java question
entirely. Rejected because no other distribution ships it (finding 4), it changes what the package
is immediately after a handover, and it grows the download to 94.5 MB for users who already have
Java.

**Install a JDK from the install script.** Blocked by CPMR0010, a Requirement (finding 2).

**Publish under a new id such as `jadx-gui`.** Rejected earlier in the investigation: Chocolatey's
naming guidelines say to reuse the id other repositories use, and Repology shows every
distribution using `jadx`.

**One combined module instead of two.** `GitHubRelease.psm1` is a source adapter; `ChocoUpdate.psm1`
is transport and AU boilerplate. Packages that scrape HTML need the second and not the first.
Keeping them apart means `antigravity-ide` and `typeless` do not import GitHub code they never
call.

## Prerequisites and open questions

- **The handover must complete before anything in `jadx/` is published.** If maintainer access is
  refused, the `jadx/` folder stays unpublished and the module work stands on its own.
- The Chocolatey API key for pushing jadx is the existing `CHOCO_API_KEY` secret; no new secret is
  needed.
- Whether to keep `Install-ChocolateyShortcut` for the start-menu entry is deferred to
  implementation. Both the existing package and `ghidra` create one, so the default is to keep it.

## Verification

- `antigravity-ide`: its nuspec is at 2.5.5, which is the current upstream version, so
  `./update.ps1` must report no update. This proves the module path resolves and that
  `Get-ValidatedContent` still parses a real response.
- `typeless`: its nuspec is at 2.1.0 while upstream is ahead, so the same run exercises the update
  path end to end — feed parse, base64-to-hex checksum conversion, and the rewrite of
  `chocolateyinstall.ps1`. Compare the rewritten file against what the pre-migration script
  produces from the same feed; they must be byte-identical. Do not push the result: 2.1.0 is still
  in moderation.
- Run both against the pre-migration scripts on the same day, so any upstream movement between
  runs cannot be mistaken for a migration defect.
- `jadx`: `Get-GitHubLatestRelease` against `skylot/jadx` must return 1.5.6, select
  `jadx-1.5.6.zip`, and read a `digest` equal to the SHA-256 the previous maintainer recorded in
  VERIFICATION.txt (`545ea2be…`) — the digest path verified against an independent source. The install path needs a Windows host, so it is verified with
  `choco install jadx -s . -f` on a Windows VM, twice: once with no JDK present (expect the
  warning, expect success) and once with a JDK 11+ present (expect no warning, expect
  `jadx --version` to run).
- The install-time behaviour on a machine without Java is the one thing that cannot be checked
  from macOS. It is also the exact condition the Chocolatey verifier reproduces, so a failure here
  is a failure there.
- This Mac has no `pwsh`, so "run locally" means either `brew install --cask powershell` plus
  `Install-PSResource AU`, or driving the existing workflows' `workflow_dispatch` trigger from a
  branch. Both workflows already declare `workflow_dispatch`.

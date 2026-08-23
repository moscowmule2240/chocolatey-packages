# Design: taking over and modernising the radare2 package

- Created: 2026-08-23
- Status: Design (not implemented)

## Context

`radare2` exists on the Chocolatey Community Repository and is five years out of
date. This design covers taking maintenance over through the Package Triage Process and
bringing the package to the current release, reusing the modules built for `jadx`.

| | |
| --- | --- |
| Latest approved on Chocolatey | **5.4.2**, approved 2021-09-26 |
| Current upstream release | **6.2.0**, published 2026-08-07 |
| Current maintainer | GustavoLCR |
| Package source | `github.com/GustavoLCR/Chocolatey-Packages/tree/master/radare2` |

Unlike `jadx`, nothing newer was ever submitted: `/packages/radare2/5.5.0` through
`/packages/radare2/6.2.0` all return 404, so no version is sitting in moderation or was
rejected. The package simply stopped being updated.

The reason is visible in the package source. The only automation it carries is
`radare2_git.ps1`, which pulls build artifacts from AppVeyor to publish `-git` snapshot
versions, and which is pinned to `vs2017`, `Python37` and `Inno Setup 5`. **There is no
updater for stable releases at all** — those were published by hand, and the hand
stopped. Upstream ships every 1.5–2 months, so the gap grew to a full major version.

## Findings

### 1. The maintainer's activity stopped

| What | Last change |
| --- | --- |
| `radare2/` directory | 2021-09-26 (`Fix r2 bind with --forcex86`) |
| The whole repository | 2023-06-20 (`Cutter 2.2.1`, `Rizin 0.5.2`) |

The maintainer did touch other packages in 2023 — Cutter and Rizin — but not radare2.
The repository itself has had no commit for three years.

`rizin` is worth a separate look later: Chocolatey serves 0.4.1 while that 2023-06-20
commit says "Rizin 0.5.2", which is the same shape as the jadx 1.5.6 case (committed but
never published). It is out of scope here.

### 2. The existing install script is sound, and smaller than it looks

`tools/chocolateyinstall.ps1` is 36 lines: `Install-ChocolateyZipPackage` for the
w32/w64 archives, then one explicit shim:

```powershell
Install-BinFile -Name r2 -Path "$installDir\$packageName64\bin\radare2.exe"
```

`tools/chocolateyuninstall.ps1` is one line: `Uninstall-BinFile -Name r2`.

That one-liner is not an omission. Chocolatey automatically creates a shim for every
`.exe` it finds in the package folder after the install script has run, and removes those
shims again when the package is uninstalled. Packages that do NOT want this must opt out
file by file — which is exactly what `ghidra` does, planting an `.ignore` next to every
extracted `.exe`. The explicit `Install-BinFile` here exists only to add the `r2` alias,
a name no executable carries; being explicit, it is also the one shim the uninstall
script must remove by hand.

The 6.2.0 archive was downloaded and listed: every `.exe` sits under `bin/` — nothing
elsewhere — so the automatic mechanism picks up exactly these **sixteen executables**:

```
r2agent  r2pm  r2r  rabin2  radare2  radiff2  rafind2  rafs2
ragg2    rahash2  rapatch2  rarun2  rasign2  rasm2  ravc2  rax2
```

An earlier draft of this design misread the one `Install-BinFile` line as "only `r2` is
reachable" and planned to enumerate `bin/*.exe`, registering each shim explicitly. That
would have re-implemented the platform mechanism and added an uninstall loop that has to
stay in agreement with it, while changing nothing a user can observe.

### 3. Scoop is current but its binary list has drifted

Scoop's `radare2` manifest is at 6.2.0 and shims twelve executables. Compared against the
archive, it is missing four: `r2pm`, `r2r`, `rafs2`, `rapatch2`. `r2pm` is radare2's own
plugin manager, so its absence is a real gap.

The cause is that Scoop's `bin` field is a hand-written list, which no one revisits when
upstream adds a binary — and Scoop has no automatic-shim mechanism to fall back on.
Chocolatey does, and it enumerates the archive as actually extracted, per architecture.
**The drift is an argument for leaning on that automatic enumeration, not for writing our
own.**

### 4. Upstream publishes three Windows architectures, all with digests

| Asset | Size | digest |
| --- | --- | --- |
| `radare2-6.2.0-w64.zip` | 12.8 MB | `sha256:adb1ffd1…` |
| `radare2-6.2.0-w32.zip` | 11.9 MB | `sha256:b06959f8…` |
| `radare2-6.2.0-w64-arm64.zip` | 12.0 MB | `sha256:a5a956b8…` |

The w64 archive was downloaded and hashed locally; the result matches the API digest
exactly. `GitHubRelease.psm1`'s `Get-AssetChecksum` therefore works here, and no
architecture needs downloading to be hashed — 36 MB saved per release.

**No Windows package manager currently ships the arm64 build.** Scoop covers 64bit and
32bit only, and the existing Chocolatey package covers the same two.

### 5. radare2 has no runtime dependency

Native executables, statically self-contained apart from the DLLs in the archive. None of
the Java questions that dominated the jadx design apply. The nuspec declares no
`<dependencies>`, exactly as the existing package does.

## Design

### Package layout

```
radare2/
├── radare2.nuspec
├── README.md
├── update.ps1
└── tools/
    ├── chocolateyinstall.ps1
    └── chocolateyuninstall.ps1
```

Identical in shape to `jadx/`, and `update.ps1` uses the same `GitHubRelease.psm1`.

### Three architectures

`Install-ChocolateyZipPackage` accepts one 32-bit and one 64-bit URL, which cannot express
a third architecture. The script therefore selects the archive itself and passes a single
url/checksum pair, the way `typeless` already does for its two:

```powershell
$isArm64 = ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') -or ($env:PROCESSOR_ARCHITEW6432 -eq 'ARM64')
if     ($env:chocolateyForceX86)               { $url = $url32;    $checksum = $checksum32    }
elseif ($isArm64)                              { $url = $urlArm64; $checksum = $checksumArm64 }
elseif ([Environment]::Is64BitOperatingSystem) { $url = $url64;    $checksum = $checksum64    }
else                                           { $url = $url32;    $checksum = $checksum32    }
```

`--x86` is tested first. When a script hands both `url` and `url64bit` to a Chocolatey
helper, `--forcex86` is honoured for free; a script that picks the URL itself must honour
`$env:chocolateyForceX86` itself. Dropping it would regress the very thing the previous
maintainer's last radare2 commit fixed (`Fix r2 bind with --forcex86`, 2021-09-26). The
arm64 test precedes the x64 one because a Windows-on-ARM machine also reports
`Is64BitOperatingSystem = $true`; ordered the other way, it would be handed the x64 build.

`au_SearchReplace` rewrites six variables and is written inline in `update.ps1`.
`Get-DualArchSearchReplace` is not used — it is fixed at the four-variable shape the other
two packages share.

### Shims: automatic, plus the r2 alias

The sixteen executables are left to Chocolatey's automatic shims. No `.ignore` file is
written anywhere in the package — exposing everything under `bin/` is the point — and
because the automatic scan covers whatever the chosen archive actually contains, each
architecture gets exactly its own set, and a release that adds or removes a binary is
tracked without a code change.

The install script registers exactly one explicit shim:

```powershell
Install-BinFile -Name 'r2' -Path (Join-Path $binPath 'radare2.exe')
```

`r2` is how the tool is invariably invoked, no executable carries that name, and the
existing package already provides it — dropping it would break anyone upgrading.

`chocolateyuninstall.ps1` stays the same single line the existing package has,
`Uninstall-BinFile -Name 'r2'`: automatic shims are removed by Chocolatey together with
the package folder, and the explicitly registered alias is the one shim that is not.

This is the opposite division of labour from `jadx`, deliberately: jadx's launchers are
`.bat` files, which the automatic mechanism ignores, so that package must register and
unregister every shim explicitly. radare2's are `.exe`, so the platform does the work.

### The archive's directory name

The zip expands to `radare2-<version>-<arch>/`, a name that changes with every release and
differs per architecture. Rather than reconstructing it, the script locates `bin/` the way
the jadx package does:

```powershell
$binPath = Get-ChildItem -Path $toolsDir -Directory -Recurse -Filter 'bin' |
           Where-Object { Test-Path (Join-Path $_.FullName 'radare2.exe') } |
           Select-Object -First 1 -ExpandProperty FullName
```

### nuspec: what is kept and what changes

Kept from the existing package, because a handover should not quietly restyle what users
already see: `id`, `title`, `authors`, `projectUrl` (`https://rada.re`), `licenseUrl`,
`docsUrl`, `bugTrackerUrl`, `tags`, `summary`, and the 7,170-character `description`.

`projectSourceUrl` is kept as well. It points at `github.com/radareorg/radare2` while
`projectUrl` points at `rada.re`, so the two genuinely differ and CPMR0041 — the rule that
flagged the jadx package — does not apply.

`iconUrl` is also kept as-is, pointing at `cdn.jsdelivr.net/gh/radareorg/radare.org/img/r2.svg`.
This departs from the other three packages, which serve an `icon.png` committed to this
repository, and the reason is licensing: `radareorg/radare.org` carries no license file at
all, and GitHub reports the radare2 repository itself as `NOASSERTION`. Copying the logo
into this repository would be redistribution under unclear terms. Referencing the upstream
file leaves that question where it belongs. The URL satisfies CPMR0058 (SVG is an accepted
format) and CPMR0076 (it is a CDN URL, not a raw GitHub one). The available PNGs are
472x199 and 100x36 — not square — so they would be a poor substitute even if the licensing
were clear.

Changed:

| Field | From | To | Why |
| --- | --- | --- | --- |
| `version` | 5.4.2 | 6.2.0 | the point of the exercise |
| `packageSourceUrl` | GustavoLCR's repo | this repository | required by the handover process |
| `owners` | GustavoLCR | moscowmule2240 | ditto |
| `copyright` | `2009-2021 …` | `2009-2026 …` | the existing value predates five years of releases |
| `releaseNotes` | the full 5.4.2 changelog, inline | `https://github.com/radareorg/radare2/releases` | an inline changelog has to be rewritten by hand every release; a URL never goes stale. The other three packages already do this |

`requireLicenseAcceptance` stays `true`. radare2 is LGPL-3.0 and the existing package sets
it; changing it during a handover would alter what users are asked to agree to, for no
reason connected to this work.

### What is not carried over

`radare2_git.ps1` — the AppVeyor snapshot publisher — is dropped. It targets a toolchain
from 2017, it publishes `-git` prerelease versions this repository has no interest in, and
the stable-release updater replaces its purpose entirely.

### Workflow

`.github/workflows/update-radare2.yml`, copied from `update-jadx.yml`: `PKG_DIR: radare2`,
`concurrency.group: update-radare2`, `GITHUB_TOKEN` passed to the AU step, and `schedule:`
commented out until the handover completes.

## Rejected alternatives

**Keep the two-architecture layout.** Simplest, and matches both the existing package and
Scoop. Rejected because upstream already builds `w64-arm64` and nobody ships it: adding it
costs one branch in the install script and makes this the only Windows package manager
that serves Windows-on-ARM users.

**Hand-write the shim list, as Scoop does.** Rejected on the evidence: Scoop's list has
drifted four binaries behind the archive it installs, `r2pm` among them. A fixed list
rots the moment upstream changes `bin/`.

**Enumerate `bin/*.exe` and register each shim with `Install-BinFile`.** The first draft
of this design. Rejected once it was checked against what Chocolatey already does: the
automatic shim scan IS that enumeration, with removal handled by the platform instead of
by a second loop in the uninstall script that has to stay in agreement with the first.

**Shim only the binaries a user is likely to type.** Requires judging which of `r2r` or
`rapatch2` is "likely", and being wrong is silent. Upstream decides what belongs in `bin/`.

**Rewrite the description while the package is being touched anyway.** Rejected: a handover
should change behaviour where it is broken and leave presentation alone, so that the
difference between the old package and the new one is reviewable.

## Prerequisites and sequencing

**The order differs from the jadx handover, deliberately.** For jadx the issue was opened
before the package had ever been installed, and the first Windows test then found a bug
that would have failed moderation. Here the package is built and verified first:

1. Implement `radare2/` and its workflow; land on `main`.
2. Push, and verify on a real Windows machine (see below).
3. Only then open the GitHub issue and send the Contact Maintainers message.
4. Seven days later, if there is no reply, contact the Site Admins.

This runs in parallel with the jadx handover, whose window closes 2026-08-29. Both
requests will therefore be open at once, and each should link its own evidence so the two
are not read as a single sweep.

Nothing is published to Chocolatey until maintainer access is granted.

## Verification

Local, before pushing:

- `radare2.nuspec` parses; no `<dependencies>`; `requireLicenseAcceptance` is `true` and
  `licenseUrl` is present (CPMR0007); `iconUrl` resolves to a 200 and is not a
  `raw.githubusercontent.com` URL (CPMR0076).
- The six replacement patterns each match exactly one line of `chocolateyinstall.ps1`, and
  rewriting them leaves the architecture-selecting `if/elseif/else` untouched — the check
  already used for the other packages.
- No `cinst` / `choco install` / `choco upgrade` anywhere under `radare2/` (CPMR0010).
- `Get-GitHubLatestRelease -Repo 'radareorg/radare2'` resolves 6.2.0 and all three assets,
  and their digests match the values recorded in finding 4.
- The w64 archive contains `.exe` files only under `bin/` (verified by listing the
  archive), so the automatic shims are exactly the sixteen named in finding 2.

On Windows, with `choco pack` re-run first:

| Case | Expected |
| --- | --- |
| `choco install radare2 --version 6.2.0 -s . -y --force` on x64 | installs the w64 archive |
| `r2 -v` | reports 6.2.0 |
| `Get-Command r2, rabin2, rasm2, rax2, r2pm` | all resolve to `C:\ProgramData\chocolatey\bin\` |
| Shim count | 17 — sixteen automatic, plus the explicit `r2` |
| `choco uninstall radare2 -y` | every shim removed; `Get-Command r2` finds nothing |

Two limits, stated rather than papered over:

- **The architecture selection cannot be unit-tested.** It lives inside
  `chocolateyinstall.ps1`, which Chocolatey executes with its own helper functions in
  scope (`Install-ChocolateyZipPackage`, `Install-BinFile`), so Pester cannot run the file
  without stubbing the whole Chocolatey environment. What the Pester suite does cover is
  `GitHubRelease.psm1` resolving radare2's three assets — the part that feeds the install
  script. The branch itself is verified by the x64 install on Windows, and by reading it.
- **The arm64 branch stays unverified.** There is no Windows-on-ARM machine to run it on.
  It is three lines and the ordering rationale is recorded above, but this design does not
  claim it has been executed.

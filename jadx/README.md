# jadx

[JADX](https://github.com/skylot/jadx) — command line and GUI tools that produce
Java source code from Android Dex and Apk files.

## Upstream

Releases: <https://github.com/skylot/jadx/releases>

The package installs `jadx-<version>.zip`, the standard release archive that
carries both `bin/jadx` and `bin/jadx-gui`. The `-with-jre-win` archive is not
used: no distribution that was checked ships it — Scoop, Homebrew and the
previous Chocolatey package all use the standard archive — and it would add
~25 MB of JRE for users who almost always already have Java.

## Java

jadx requires 64-bit Java 11 or later, and this package declares no Java
dependency.

The Chocolatey Community Repository has no package meaning "any Java 11 or
later". The `javaruntime` metapackage resolves to `jre8`, which is too old for
jadx, and Chocolatey's virtual-package feature — which would let one dependency
be satisfied by any of several JDKs — is documented as not yet implemented.
Depending on a specific id such as `temurin11` would install a second JDK
alongside whatever the user already runs, and dependency resolution matches on
package id, so having `temurin21` would not satisfy it.

Every other Java 11+ tool on the repository does the same. `ghidra`, `zap`,
`jenkins` and `openrefine` all declare no Java dependency.

There is a further reason, which a dependency could never cover: most JDKs on a
developer's machine are not installed through Chocolatey at all. During testing
this package found a working Temurin 21 that `mise` had installed under
`%LOCALAPPDATA%\mise\installs\java\`, and which `choco list` does not report.
A `temurin11` dependency would have installed a second JDK next to it, because
dependency resolution matches on package id and can only see packages Chocolatey
itself manages. Probing `java.exe` on PATH finds the runtime regardless of which
tool installed it.

The install script detects Java and prints a warning when it is missing or older
than 11. It does not fail the installation: unpacking and shim registration do
not need Java, and failing there would break the Chocolatey verifier, which runs
without a JDK.

## History

The `jadx` id was previously maintained by [FranklinYu](https://github.com/franklinyu/chocolatey-packages).
Versions 1.5.3 and 1.5.6 were both closed by the moderation bot after their
verification runs failed: the package depended on `javaruntime [8,9)`, and the
Oracle JRE 8 installer hung during the silent install and hit the 2700-second
execution timeout, taking jadx down with it. Maintenance was transferred
following the Chocolatey Package Triage Process.

## Maintenance notes

- `update.ps1` reads the latest GitHub release through
  `scripts/GitHubRelease.psm1`. The checksum comes from the release asset's
  `digest` field, so no download is needed to hash the 69 MB archive.
- The archive unpacks to `jadx-<version>/`, so the install script searches for
  `bin/jadx.bat` rather than assuming a fixed path — the directory name changes
  with every release.
- Shims are registered explicitly with `Install-BinFile` and must be removed
  explicitly with `Uninstall-BinFile`.
- CPMR0010 is a plain string match: never write a Chocolatey install command in
  these scripts, not even inside a comment or a warning message.
- **Never pipe `java -version` through `2>&1`.** It writes to stderr even when it
  succeeds, and under `$ErrorActionPreference = 'Stop'` each captured line
  becomes an ErrorRecord that aborts the install — so a working JDK fails the
  package. Use `Start-Process -RedirectStandardError` and read the file. This was
  shipped broken once, on 2026-08-22: the shims were registered and then the
  install died on `openjdk version "21.0.11"`, which is a healthy JDK. The same
  applies to any native command whose normal output goes to stderr.
- The CI `Test install / uninstall` step only runs when AU produced a `.nupkg`,
  which means it is skipped whenever the nuspec already matches upstream. A new
  package therefore gets no install coverage from CI on its first commit — test
  it on a real Windows machine before trusting it.
- When re-testing after a fix, run `choco pack` again. `choco install -s .`
  installs from the `.nupkg` in the directory, not from the working tree, so a
  stale package silently reproduces the bug you just fixed.

## Verified on Windows, 2026-08-23

Against 1.5.6 with `choco install jadx --version 1.5.6 -s . -y --force`:

| Case | Result |
| --- | --- |
| Java 21 present (Temurin via mise) | installs, no warning |
| `jadx --version` | `1.5.6` |
| Shims and start-menu shortcut | `jadx.exe`, `jadx-gui.exe`, `JADX GUI.lnk` under `CommonPrograms` |
| `choco uninstall jadx -y` | both shims removed, `Get-Command jadx` finds nothing |
| **No Java on PATH** | **warns, and the install still succeeds** |

The last row is the one that matters: it is the condition the Chocolatey verifier
runs under, and a failure there is what closed 1.5.3 and 1.5.6.

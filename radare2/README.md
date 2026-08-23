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

Three, where Scoop covers two. Upstream builds `w64-arm64` and no Windows
package manager was shipping it, so a Windows-on-ARM machine had no packaged radare2 at all.

`Install-ChocolateyZipPackage` accepts one 32-bit and one 64-bit URL and cannot
express a third, so the install script selects the archive itself. Two
consequences worth remembering before editing that block:

- **`$env:chocolateyForceX86` must be checked by hand.** The helper honours
  `--x86` for free only when it is handed both URLs; without the check, `--x86`
  installs the 64-bit build.
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
invariably invoked. It is therefore
registered with `Install-BinFile` and, because explicit shims are not cleaned up
automatically, removed with `Uninstall-BinFile`.

Scoop takes the other approach — a hand-written `bin` list — and it has drifted
four binaries behind the archive it installs: `r2pm`, `r2r`, `rafs2` and
`rapatch2` are missing there. `r2pm` is radare2's own plugin manager.

## Verified on Windows, 2026-08-23

Against 6.2.0 with `choco install radare2 --version 6.2.0 -s . -y --force`:

| Case | Result |
| --- | --- |
| x64 install | selects `radare2-6.2.0-w64.zip`; `r2 -v` reports `windows-x86_64` |
| `--x86` on the same x64 machine | selects `radare2-6.2.0-w32.zip`; `r2 -v` reports `windows-x86_32` |
| Shims | 17 — sixteen created by ShimGen from `bin/*.exe`, plus the explicit `r2` |
| `r2pm`, `r2r`, `rafs2`, `rapatch2` | present — these are the four Scoop's hand-written list omits |
| `choco uninstall radare2 -y` | all 17 gone, though only `r2` is removed explicitly |

Two design choices were confirmed rather than assumed by this run. The automatic
shims really do cover every `.exe` in the extracted archive, so enumerating them
here would have been redundant — and they are removed with the package, so the
one-line uninstall script is sufficient. And `--x86` really does need the
explicit `$env:chocolateyForceX86` check: the branch picked the 32-bit archive on
a 64-bit machine only because that test comes first.

The arm64 branch remains unverified — no Windows-on-ARM hardware was available.

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
- CPMR0010 is a plain string match for `cinst`, `choco install` and `choco upgrade`:
  never write one in `tools/*.ps1`, not even inside a comment. It applies to the
  packaged scripts, and `<files>` packages `tools\**` only — so the install
  commands in this README are outside its reach. Scan `radare2/tools/`, not
  `radare2/`, or the README's own instructions come back as false positives.
- The CI `Test install / uninstall` step only runs when AU produced a `.nupkg`,
  so a package whose nuspec already matches upstream gets no install coverage
  from CI — test it on a real Windows machine. The same gate governs publishing:
  AU only acts on versions newer than the nuspec, so a scheduled run no-ops
  while the nuspec matches upstream. See "The first push of a package is always
  manual" in the repo README.
- When re-testing after a fix, run `choco pack` again. `choco install -s .`
  installs from the `.nupkg` in the directory, not from the working tree.

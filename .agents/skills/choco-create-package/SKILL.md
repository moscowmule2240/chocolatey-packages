---
name: choco-create-package
description: Use when building, verifying or first-publishing a package in this Chocolatey packages repository, when choco push returns 409 Conflict for a version that is not on the site, or when an install script fails under Windows PowerShell 5.1. Triggers - 「パッケージを作る」「choco push が 409」「初回 push」「モデレーション」.
---

# Create a package

Builds, verifies and publishes one package, then puts it on automation. Commands live in
`README.md`; this skill says which to run when, and what to avoid. The rules in
`AGENTS.md` apply throughout. Reached without `choco-task-add-package` for a package that
is not in this repository yet? Run its section 1 first: the software may already be
packaged under another id, or be waiting in moderation.

## Start from the example with the same upstream shape

| Upstream ships | Copy | Shows |
| --- | --- | --- |
| One architecture-independent zip on GitHub Releases | `jadx/` | `scripts/GitHubRelease.psm1`; warning, not failing, when a runtime (Java) is missing |
| Per-architecture archives on GitHub Releases | `radare2/` | x64 / x86 / arm64 selection; explicit `--x86`; automatic shims plus one alias |
| An installer plus an electron-builder update feed | `typeless/` | version and sha512 from the feed; a per-user install |
| Links on an official download page | `antigravity-ide/` | reading installer URLs from the page |

## Procedure

1. Copy the example directory to `<id>/`.
2. Replace everything package-specific: the nuspec (id, title, version, URLs,
   description, tags, `packageSourceUrl` pointing at this repository, owners), `tools/`,
   `update.ps1` and `README.md`.
3. Verify on Windows: `README.md` → "Build & test locally (on Windows)". Run
   `choco pack` again after every change. Record what was verified, and where upstream
   versions come from, in `<id>/README.md` (see `jadx/README.md`).
4. First version: push the build verified in step 3 by hand, after the person's
   go-ahead: `README.md` → "Publish (moderation)" and `README.md` →
   "The first push of a package is always manual".
5. Follow moderation (below).
6. After the first approval, add automation: copy an existing
   `.github/workflows/update-jadx.yml` to `update-<id>.yml`; replace the id in `name`,
   the header comment, `concurrency.group` and `with.package`; add the package to the Packages and Automation tables in `README.md`. Commit
   it and land it on `main` as `AGENTS.md` describes. Pushing it needs the person's
   go-ahead: the schedule starts with the push, and a run publishes a newer upstream
   version that is not yet on the community repository. Once it is on `origin`, and
   again with the person's go-ahead, run it once
   (`gh workflow run update-<id>.yml --ref main`) and confirm `Preflight` and
   `Validate nuspec against community repository rules` are green.

## Rules for every package

| Rule | Otherwise |
| --- | --- |
| Description at most 4,000 characters (CPMR0026) | `choco push` returns a bare `409 Conflict`, like a duplicate version |
| Title differs from the id (CPMR0050) | Flagged in moderation |
| No `choco install` / `choco upgrade` text under `tools/` (CPMR0010) | Requirement failure |
| `tools/*.ps1` runs under Windows PowerShell 5.1: no three-argument `Join-Path`, no ternary, no `??` | The install fails |
| In `tools/*.ps1`, never capture a native command's stderr with `2>&1`; use `Start-Process -RedirectStandardError` (see `jadx/tools/chocolateyinstall.ps1`) | Commands that write to stderr on success (`java -version`) fail the install |
| Checksums from the GitHub release asset's `digest` | Downloading archives only to hash them |
| If the install script picks the archive itself, honour `$env:chocolateyForceX86` | `--x86` stops working |
| Every `.exe` in the package is shimmed automatically. Use `Install-BinFile`, paired with `Uninstall-BinFile`, only for what that misses: an alias (`radare2/`'s `r2`) or a non-`.exe` launcher such as a `.bat` (`jadx/`) | A launcher missing from `PATH`, or duplicate and orphaned shims |
| No dependency on a metapackage that pins an old runtime (`javaruntime` resolves to `jre8`); the verifier has no JDK, so warn and continue | The old runtime's installer times out in verification and the version is auto-rejected |
| Commercial or trial software: say so in the description; tags `trial` and `license` | Raised by the moderator |
| The icon URL is not a raw GitHub URL (CPMR0076, a Requirement); jsDelivr is fine. Prefer PNG or SVG (CPMR0058, a Suggestion) | CPMR0076 blocks approval, and `choco pack` with the validation extension stops on it; CPMR0058 is only noted |

## When `choco push` returns 409 Conflict

The response body is IIS's generic page, so it never says why. If the version is not in
the version history:

1. Run `choco pack` with the validation extension installed. A Requirement violation
   (for example CPMR0026) is the usual cause.
2. Request `https://community.chocolatey.org/packages/<id>/<version>` directly. A 200
   means a rejected submission holds the number, even though the version history hides
   it; only the Site Admins can release it (`choco-take-over-package`, step 7).

Do not work around a 409 with a package-fix version (`x.y.z.YYYYMMDD`): the Chocolatey
documentation reserves that for fixing approved packages, and it hides the cause.

## Moderation

- `Ready`: automated checks passed, waiting for a human. Safe to wait; do not ask anyone
  to hurry it.
- `Waiting for Maintainer`: 20 days without a response brings a warning, 15 more an
  automatic rejection. Draft an answer for the review comments on the package page; the
  person posts it, or approves posting it.

# Chocolatey packages

A personal collection of community-maintained [Chocolatey](https://chocolatey.org)
packages — one folder per package.

## Packages

| Package | Description | Details |
|---------|-------------|---------|
| [`antigravity-ide`](antigravity-ide/) | Google Antigravity IDE (editor surface) | [package README](antigravity-ide/README.md) |
| [`jadx`](jadx/) | JADX — Dex to Java decompiler (CLI + GUI) | [package README](jadx/README.md) |
| [`radare2`](radare2/) | radare2 — reverse engineering framework and toolset | [package README](radare2/README.md) |
| [`typeless`](typeless/) | Typeless — AI voice dictation for Windows | [package README](typeless/README.md) |

## Repo layout

Each package lives in its own folder named after its Chocolatey id:

```
<package-id>/
├── <package-id>.nuspec          # package metadata
├── README.md                    # package-specific notes (upstream source, quirks)
├── update.ps1                   # AU updater: detect latest version, repack (optional)
└── tools/
    ├── chocolateyinstall.ps1    # install logic
    └── chocolateyuninstall.ps1  # uninstall logic (if needed)

scripts/
├── Check-ChocolateyStatus.ps1       # shared: is this version already published?
├── ChocoUpdate.psm1                 # shared: retrying fetch + dual-arch replacements
└── GitHubRelease.psm1               # shared: GitHub Releases as an update source

tests/                               # Pester tests for the shared modules
.github/workflows/
├── _update-package.yml              # shared: the update job every package calls
├── update-<package-id>.yml          # per package: schedule, concurrency, secret
└── test.yml                         # Pester tests for the shared modules
```

The two modules under `scripts/` hold what every `update.ps1` would otherwise
duplicate. `ChocoUpdate.psm1` owns the HTTP transport: it retries a response that
arrives intact but incomplete — a 200 whose body is truncated — and, when it
finally gives up, reports the status, the body length and the last 200
characters. That diagnostic has been what identified more than one real failure,
so it should not be trimmed. `GitHubRelease.psm1` turns a repository into a
version, an asset and a checksum, taking the checksum from the release asset's
`digest` field so no download is needed to compute it.

Run the tests with `Invoke-Pester ./tests`; CI runs them on `windows-latest` for
every change under `scripts/`, `tests/` or any `update.ps1`.

---

## Prerequisites

- A **Windows** machine with Chocolatey installed (`choco pack` / `choco push` are Windows-only).
- A free account on https://community.chocolatey.org and your **API key** (Account → API Keys).

## Before the first push: confirm the id is free

A Chocolatey package id is global and belongs to whoever first pushes it. **Check that
the package page returns 404** before claiming an id:

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://community.chocolatey.org/packages/<package-id>
# 404 = free to use   |   200 = already taken
```

> ⚠️ Don't rely on the OData feed (`/api/v2/FindPackagesById()?id='<id>'`) alone — it
> only returns **approved & listed** versions, so a submission still **in moderation**
> shows up as 0 results even though the id is already reserved. The `/packages/<id>`
> page reflects moderation-pending submissions; the feed does not.

Search by the software's name as well
(`https://community.chocolatey.org/packages?q=<name>`): an id can belong to different
software — `zed` is the SpiceDB CLI — and the software may already be packaged under
another id, as the Zed editor is under `zed-editor`.

## Build & test locally (on Windows)

```powershell
choco install chocolatey-community-validation.extension -y   # once per machine
cd <package-id>
choco pack                                       # -> <package-id>.<version>.nupkg
choco install <package-id> -s . -y --force       # test install from the local dir
choco uninstall <package-id> -y                  # test uninstall
```

With the validation extension installed, `choco pack` applies the community
repository's Requirements and stops on a violation, for example
`ERROR: CPMR0026: The description has a length of 6,894 characters`. The push endpoint
reports the same violation only as a bare `409 Conflict`.

Run `choco pack` again after every change: `choco install -s .` installs the `.nupkg`
in the directory, not the working tree.

## Publish (moderation)

```powershell
choco apikey --key <YOUR_API_KEY> --source https://push.chocolatey.org/
cd <package-id>
choco push <package-id>.<version>.nupkg --source https://push.chocolatey.org/
```

After pushing you'll get emails as it moves through validation → verification →
virus scan → human review. If a step fails you have up to 35 days to fix and re-push.
See https://docs.chocolatey.org/en-us/community-repository/moderation/

### The first push of a package is always manual

Enabling `schedule:` is not enough to get a new package onto Chocolatey. AU only
acts on versions **newer** than the nuspec, and every publishing step in the
workflows is gated on `steps.pkg.outputs.found == 'true'` — which is only true
when AU actually built a `.nupkg`. A package whose nuspec already matches the
current upstream release therefore no-ops on every scheduled run, forever, and
nothing is ever pushed.

So the version the nuspec carries reaches the repository by hand, with the
commands above, and the workflow publishes from the *next* upstream release.
A nuspec that is already behind upstream is the exception: the first scheduled
run builds and publishes the newer release.

## Automation (auto-update on a schedule)

A package keeps itself up to date through a short workflow,
`.github/workflows/update-<package-id>.yml`, that calls the shared job in
`.github/workflows/_update-package.yml`. The per-package file holds only what
differs between packages: the schedule, the concurrency group,
`permissions: contents: write` for the version-bump commit, and `CHOCO_API_KEY`
passed explicitly under `secrets:`. Adding a package means adding such a file:
copy an existing caller, replace the package id everywhere it appears — `name`,
the header comment, `concurrency.group` and `with.package`. Then add the
package to the table below.

| Package | Workflow | Schedule |
|---------|----------|----------|
| antigravity-ide | [`update-antigravity-ide.yml`](.github/workflows/update-antigravity-ide.yml) | every 5 min |
| typeless | [`update-typeless.yml`](.github/workflows/update-typeless.yml) | every 5 min |
| jadx | [`update-jadx.yml`](.github/workflows/update-jadx.yml) | every 5 min |
| radare2 | [`update-radare2.yml`](.github/workflows/update-radare2.yml) | every 5 min |

Each run — on the schedule in the table above, or manual via *Actions → Run workflow*
— does the following on a `windows-latest` runner:

1. **checks what the calling workflow supplies** (`Preflight`): the run fails at
   once if `CHOCO_API_KEY` is empty or the run cannot push to the repository
   (`git push --dry-run`). Both are otherwise used only when a new version is
   built, so a caller that left either out would stay green until the next
   upstream release,
2. installs the [Chocolatey **AU**](https://github.com/chocolatey-community/chocolatey-au) module
   and the [community validation extension](https://community.chocolatey.org/packages/chocolatey-community-validation.extension),
3. **validates the committed nuspec** against the community repository's rules by
   packing it into a scratch directory — every run, including the ones where no new
   version exists. A Requirement violation fails the run with the rule, e.g.
   `ERROR: CPMR0026: The description has a length of 6,894 characters`, repeated as
   a GitHub error annotation. Without this, the push endpoint reports the same
   violation as a bare `409 Conflict` (see `radare2/README.md`). Guidelines are not
   reported here; they arrive with the moderation emails,
4. runs the package's `update.ps1` — detects the latest upstream version, and if
   it's newer than the nuspec, rewrites the install script's `url`/`checksum` +
   the nuspec `<version>` and repacks the `.nupkg`,
5. test-installs and uninstalls the new package,
6. checks whether that version is already on Chocolatey.org (`scripts/Check-ChocolateyStatus.ps1`),
7. **pushes** it, and
8. commits the version bump back to the repo with `[skip ci]`.

> Neither package needs a **scraping service**: antigravity-ide reads its installer
> URLs straight off the official download page, and typeless reads the version from
> electron-builder's `latest.yml` update feed. Version detection is free and key-less
> for both.

### Required setup before it can publish

1. **Create a Chocolatey account** and generate an API key (Account → API Keys).
2. Add it as a repo secret: *Settings → Secrets and variables → Actions →
   New repository secret*, name **`CHOCO_API_KEY`**. (This is something only you
   can do — never paste the key into code or commits.)

Until that secret exists every run fails at the `Preflight` step. Also do the
**first publish manually** (see *Publish* above) — AU only
acts on versions *newer* than the nuspec, so it never pushes the version already in
the nuspec; it publishes from the next upstream release onward.

## Conventions & notes

- **`<owners>` in the nuspec is not shown on the community feed** ("nuspec value not
  used on community feed"). The package is owned by the *account that pushed it*, not
  by the `<owners>` value — set it for documentation, but don't rely on it for display
  or ownership.
- `<authors>` should credit the upstream software author; the packaging maintainer is
  the pushing account, not necessarily the author.
- An `iconUrl` is optional. Moderation treats a missing icon as a guideline, not a
  blocker; host one in your own repo if you want it.
- Binaries downloaded at install time are never committed — see `.gitignore`.

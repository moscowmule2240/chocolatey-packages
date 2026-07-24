# Chocolatey packages

A personal collection of community-maintained [Chocolatey](https://chocolatey.org)
packages — one folder per package.

## Packages

| Package | Description | Details |
|---------|-------------|---------|
| [`antigravity-ide`](antigravity-ide/) | Google Antigravity IDE (editor surface) | [package README](antigravity-ide/README.md) |
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

scripts/Check-ChocolateyStatus.ps1   # shared: is this version already published?
.github/workflows/                   # one CI workflow per automated package
```

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

## Build & test locally (on Windows)

```powershell
cd <package-id>
choco pack                                       # -> <package-id>.<version>.nupkg
choco install <package-id> -s . -y --force       # test install from the local dir
choco uninstall <package-id> -y                  # test uninstall
```

## Publish (moderation)

```powershell
choco apikey --key <YOUR_API_KEY> --source https://push.chocolatey.org/
cd <package-id>
choco push <package-id>.<version>.nupkg --source https://push.chocolatey.org/
```

After pushing you'll get emails as it moves through validation → verification →
virus scan → human review. If a step fails you have up to 35 days to fix and re-push.
See https://docs.chocolatey.org/en-us/community-repository/moderation/

## Automation (auto-update on a schedule)

A package can keep itself up to date via a GitHub Actions workflow under
`.github/workflows/` — one per package:

| Package | Workflow | Schedule |
|---------|----------|----------|
| antigravity-ide | [`update-antigravity-ide.yml`](.github/workflows/update-antigravity-ide.yml) | every 5 min |
| typeless | [`update-typeless.yml`](.github/workflows/update-typeless.yml) | **paused** — manual only until the first publish is approved |

Each run — on the schedule in the table above, or manual via *Actions → Run workflow*
— does the following on a `windows-latest` runner:

1. installs the [Chocolatey **AU**](https://github.com/chocolatey-community/chocolatey-au) module,
2. runs the package's `update.ps1` — detects the latest upstream version, and if
   it's newer than the nuspec, rewrites the install script's `url`/`checksum` +
   the nuspec `<version>` and repacks the `.nupkg`,
3. test-installs and uninstalls the new package,
4. checks whether that version is already on Chocolatey.org (`scripts/Check-ChocolateyStatus.ps1`),
5. **pushes** it (only if `CHOCO_API_KEY` is set — see below), and
6. commits the version bump back to the repo with `[skip ci]`.

> Neither package needs a **scraping service**: antigravity-ide reads its installer
> URLs straight off the official download page, and typeless reads the version from
> electron-builder's `latest.yml` update feed. Version detection is free and key-less
> for both.

### Required setup before it can publish

1. **Create a Chocolatey account** and generate an API key (Account → API Keys).
2. Add it as a repo secret: *Settings → Secrets and variables → Actions →
   New repository secret*, name **`CHOCO_API_KEY`**. (This is something only you
   can do — never paste the key into code or commits.)

Until that secret exists the workflow runs fine but **skips the push** (it logs a
warning). Also do the **first publish manually** (see *Publish* above) — AU only
acts on versions *newer* than the nuspec, so it never pushes the version already in
the nuspec; it takes over from the next upstream release onward. (`typeless` is at
that stage now; `antigravity-ide` is published and auto-updating.)

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

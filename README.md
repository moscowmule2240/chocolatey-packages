# Chocolatey packages

A personal collection of community-maintained [Chocolatey](https://chocolatey.org)
packages — one folder per package.

## Packages

| Package | Description | Details |
|---------|-------------|---------|
| [`antigravity-ide`](antigravity-ide/) | Google Antigravity IDE (editor surface) | [package README](antigravity-ide/README.md) |

## Repo layout

Each package lives in its own folder named after its Chocolatey id:

```
<package-id>/
├── <package-id>.nuspec          # package metadata
├── README.md                    # package-specific notes (upstream source, quirks)
└── tools/
    ├── chocolateyinstall.ps1    # install logic
    └── chocolateyuninstall.ps1  # uninstall logic (if needed)
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

# typeless

Community-maintained Chocolatey package for **Typeless** — an AI voice dictation app
that turns natural speech into finished, ready-to-send text inside any Windows
application. It downloads the official `Typeless-<version>-<arch>-Setup.exe` from the
vendor's servers at install time.

> **Account required.** Typeless needs an account to use. There is a free tier with a
> weekly word allowance; unlimited use is a paid subscription. This package installs
> the application only — it does not include or provide a subscription.
>
> This package is **not** affiliated with or endorsed by Typeless. "Typeless" is a
> trademark of its respective owner.

## Upstream layout

The download page (`/downloads`) has no direct links: its buttons call
`https://www.typeless.com/desktop/<platform>/download`, which redirects to the real
artifact on `typeless-static.com`. The app is built with **electron-builder**, which
also publishes an auto-update feed next to the installers:

| Resource | URL |
|---|---|
| Update feed — windows-x64 | `https://typeless-static.com/desktop-release/latest.yml` |
| Update feed — windows-arm64 | `https://typeless-static.com/desktop-release/arm64.yml` |
| Installer | `https://typeless-static.com/desktop-release/Typeless-<version>-<arch>-Setup.exe` |

Each feed carries the version, the exact artifact filename and its **sha512**, so
`update.ps1` reads both rather than scraping the marketing site. Nothing is guessed —
the filename comes from the feed's `path:`, and the checksum is the feed's own digest
(base64 in the feed, converted to hex for Chocolatey). That also means a new release
costs no bandwidth: there is no need to download ~270 MB of installers to re-hash
them.

Two upstream quirks worth knowing about:

> - The arm64 feed is `arm64.yml`, **not** the `latest-arm64.yml` that
>   electron-builder uses by default (that URL 404s here).
> - Both feeds are served as `application/x-www-form-urlencoded`, not as text. PowerShell
>   only gives `Invoke-WebRequest` a `[string]` `.Content` for text-ish content types, so
>   these responses arrive as `[byte[]]` and have to be UTF-8 decoded by hand — casting
>   with `[string]` silently yields `"112 100 100 ..."` (the decimal byte values joined by
>   spaces) instead of the document.

Releases are published one architecture at a time, so `update.ps1` refuses to build a
package when the two feeds report different versions — it skips that run and picks the
release up once both sides have landed.

The installer is **NSIS 3.04** (electron-builder's default Windows target), so the
silent switch is `/S` for both install and uninstall.

## Updating to a new upstream version

**Automated.** The [`update-typeless.yml`](../.github/workflows/update-typeless.yml)
workflow runs `update.ps1` on a schedule and, on a new release, bumps the
`url`/`checksum`/`<version>` and repacks automatically — see the repo-level
[Automation section](../README.md#automation-auto-update-on-a-schedule).

**Architectures:** one nupkg covers both **windows-x64** and **windows-arm64** —
`chocolateyinstall.ps1` picks the right build at install time (ARM64 is detected via
`PROCESSOR_ARCHITECTURE` / `PROCESSOR_ARCHITEW6432`, so it works even when Chocolatey
runs as an emulated x64 process on ARM hardware).

### Manual update / local test

```powershell
Install-Module AU -Scope CurrentUser   # one-time
cd typeless
./update.ps1                            # detect latest, rewrite url/checksum, repack
```

Or fully by hand: read the new version, filename and base64 `sha512` out of
`latest.yml` / `arm64.yml`, convert each digest to hex, and edit
`tools/chocolateyinstall.ps1` (URLs + checksums) and `<version>` in `typeless.nuspec`.

```bash
# base64 sha512 from the feed -> the hex form Chocolatey expects
curl -s https://typeless-static.com/desktop-release/latest.yml
python3 -c "import base64,sys; print(base64.b64decode(sys.argv[1]).hex())" '<base64>'
```

# antigravity-ide

Community-maintained Chocolatey package for **Google Antigravity IDE** — Google's
agentic, agent-first AI IDE that integrates AI agents across the editor, terminal, and
browser (powered by Gemini 3). It downloads the official `Antigravity IDE.exe` from
Google's servers at install time.

> **Relationship to other Antigravity packages:** since Antigravity 2.0, Google ships
> the platform as separate downloads ([official download page](https://antigravity.google/download)):
> the main app — [`antigravity`](https://community.chocolatey.org/packages/antigravity)
> (v2.x) — plus a standalone **CLI**, **IDE**, and **SDK**. This package is the
> standalone **IDE** download (`Antigravity IDE.exe`), distinct from the `antigravity`
> main-app build (`Antigravity-x64.exe`). In 1.x, `antigravity` *was* the IDE.
>
> This package is **not** affiliated with or endorsed by Google. "Antigravity",
> "Gemini" and "Google" are trademarks of Google LLC.

## Updating to a new upstream version

**Automated.** The [`update-antigravity-ide.yml`](../.github/workflows/update-antigravity-ide.yml)
workflow runs `update.ps1` every 5 minutes and on new releases bumps the `url`/`checksum`/
`<version>` and repacks automatically — see the repo-level
[Automation section](../README.md#automation-auto-update-on-a-schedule).

**Architectures:** one nupkg covers both **windows-x64** and **windows-arm64** —
`chocolateyinstall.ps1` picks the right build at install time (ARM64 is detected via
`PROCESSOR_ARCHITECTURE` / `PROCESSOR_ARCHITEW6432`, so it works even when Chocolatey
runs as an emulated x64 process on ARM hardware).

`update.ps1` finds the latest version without any scraping service. It asks the IDE's
own update service — the endpoint the installed IDE polls — for the latest stable
release of each architecture:

```
https://antigravity-ide-auto-updater-974169037036.us-central1.run.app/api/update/win32-x64-user/stable/latest
https://antigravity-ide-auto-updater-974169037036.us-central1.run.app/api/update/win32-arm64-user/stable/latest
```

Each answer is JSON whose `url` is the installer,
`.../antigravity/stable/<version>-<build>/windows-<arch>/Antigravity IDE.exe`. The
script takes `<version>` from that path (the JSON's `productVersion` is the editor base
version, not the package version), stores the URL with the space encoded as `%20`, and
re-hashes both binaries on a new release (hashing happens in `au_BeforeUpdate`, so the
~200 MB downloads only occur on a real update). The `-user` platforms are the per-user
installers; the system-wide `win32-x64` / `win32-arm64` answer HTTP 400 with an empty body.

The [download page](https://antigravity.google/download) is not used: its download
links have lagged its own version label (2.5.5 links under a 2.6.0 label) while the
update service already served 2.6.0. Homebrew's `antigravity-ide` cask reads the same
service, so a change to the endpoint is likely to show up there as well.

Rules the answers must pass:

- The URL must match `$Stable/<version>-<build>/windows-<arch>/Antigravity IDE.exe`,
  with `$Stable` =
  `https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable`. Anything
  else — an empty body, HTML, another host or path, the other architecture — counts
  as a bad answer.
- Both architectures must name the same `<version>-<build>`. During a rollout the two
  requests can disagree; the run then fails, and the next scheduled run tries again.
- The answer must carry a 64-hex-digit `sha256hash`. It is the SHA-256 of the `.exe`
  (despite the answer's `displayName` saying "(.zip)"), and the installed IDE checks
  its downloads against it. `au_BeforeUpdate` hashes both downloaded installers and
  fails the run when either differs from the service's value.

Each request goes through the `Get-ValidatedContent` helper: a bad answer is treated
exactly like a failed request and retried after 5s / 15s / 30s, each retry adding a
cache-buster query param plus `Cache-Control: no-cache`. (`Invoke-WebRequest
-MaximumRetryCount` doesn't help here — it only retries HTTP *error* statuses.) If all
four attempts fail it throws with the status code, body length and the last 200 bytes
of the response, so the CI log shows *why* the lookup failed rather than just that it
did.

### Manual update / local test

```powershell
Install-Module AU -Scope CurrentUser   # one-time
cd antigravity-ide
./update.ps1                            # detect latest, rewrite url/checksum, repack
```

Or fully by hand: download the new `Antigravity IDE.exe`, `shasum -a 256` it, and
edit `tools/chocolateyinstall.ps1` (URL + checksum) and `<version>` in
`antigravity-ide.nuspec`.

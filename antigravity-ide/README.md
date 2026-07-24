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

`update.ps1` finds the latest version without any scraping service: a **single**
request to the [download page](https://antigravity.google/download) returns HTML that
already embeds both per-arch installer URLs as plain string literals, so the script
matches the `windows-x64` and `windows-arm64`
`.../antigravity/stable/<version>-<build>/.../Antigravity%20IDE.exe` URLs directly in
the page, takes `<version>` from the x64 match, and re-hashes both binaries on a new
release (hashing happens in `au_BeforeUpdate`, so the ~230 MB downloads only occur on a
real update). Until ~2026-07-20 the page was a JavaScript SPA that hid those URLs in a
content-hashed `main-*.js` bundle and needed a two-step scrape; the site was rebuilt on
Astro and that bundle no longer exists.

Both regexes are anchored to `$Stable` —
`https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable` — so the match
can't drift onto the unrelated **antigravity-hub** build that the same page links from
`storage.googleapis.com`.

The fetch goes through the `Get-ValidatedContent` helper because antigravity.google is
served through Google Frontend with a ~10-minute shared edge cache that occasionally
answers `200` with a body missing the markup we scrape (~3% of CI runs). A body that
doesn't yield both URLs is treated exactly like a failed request: retried after 5s /
15s / 30s, each retry adding a cache-buster query param plus `Cache-Control: no-cache`
so the edge revalidates instead of replaying the same bad copy. (`Invoke-WebRequest
-MaximumRetryCount` doesn't help here — it only retries HTTP *error* statuses.) If all
four attempts fail it throws with the status code, body length and the last 200 bytes
of the response, so the CI log shows *why* the scrape failed rather than just that it
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

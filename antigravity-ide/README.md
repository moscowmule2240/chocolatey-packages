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
workflow runs `update.ps1` daily and on new releases bumps the `url`/`checksum`/
`<version>` and repacks automatically — see the repo-level
[Automation section](../README.md#automation-auto-update-on-a-schedule).

`update.ps1` finds the latest version without any scraping service: the IDE's
Windows x64 installer URL is a string literal in the download page's `main-*.js`
bundle, so it reads the page → finds the bundle → extracts
`.../antigravity/stable/<version>-<build>/windows-x64/Antigravity%20IDE.exe`.

### Manual update / local test

```powershell
Install-Module AU -Scope CurrentUser   # one-time
cd antigravity-ide
./update.ps1                            # detect latest, rewrite url/checksum, repack
```

Or fully by hand: download the new `Antigravity IDE.exe`, `shasum -a 256` it, and
edit `tools/chocolateyinstall.ps1` (URL + checksum) and `<version>` in
`antigravity-ide.nuspec`.

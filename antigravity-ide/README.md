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

The IDE download URL is version-pinned (no public "latest" manifest found). Grab the
new `Antigravity IDE.exe` URL (e.g. from the hub app's "install IDE" prompt), then
recompute the checksum and bump the nuspec `<version>`:

```bash
URL='https://edgedl.me.gvt1.com/edgedl/release2/.../windows-x64/Antigravity%20IDE.exe'
curl -fsSL -o ide.exe "$URL" && shasum -a 256 ide.exe   # -> SHA256 for chocolateyinstall.ps1
```

Then update `tools/chocolateyinstall.ps1` (URL + checksum) and `<version>` in
`antigravity-ide.nuspec`.

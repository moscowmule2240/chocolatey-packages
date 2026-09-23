# Chocolatey packages

Packages maintained by moscowmule2240 on the Chocolatey Community Repository, and the
automation that keeps them current. `README.md` is the reference for commands; this
file holds the rules every change follows.

## Map

- `<package-id>/` — one directory per package: the nuspec, `tools/` (install scripts),
  `update.ps1` (AU updater) and `README.md` (upstream, history, verification).
- `scripts/` — PowerShell modules shared by the updaters; `tests/` — their Pester tests.
- `.github/workflows/_update-package.yml` — the update job every package runs;
  `update-<package-id>.yml` — each package's caller (schedule, concurrency, secret);
  `test.yml` — the Pester suite.
- `docs/superpowers/` — design specs and implementation plans.

## Rules

- Pushing to `origin`, pushing a package to the community repository (`choco push`),
  starting a workflow run that can publish (`gh workflow run update-<id>.yml`), and
  anything that reaches other people — issues, pull requests, comments, forms, email —
  need the person's go-ahead each time. A run publishes when upstream is ahead of the
  nuspec and that version is not yet on the community repository.
- Make code changes in a git worktree; `main` receives them by fast-forward only.
- Commits are signed. If signing fails, ask for the signing agent to be unlocked;
  never disable signing.
- Text committed here — comments, docs, commit messages — is English, without a first person.
- `tools/*.ps1` runs under Windows PowerShell 5.1; `update.ps1` and `scripts/` run under
  PowerShell 7. The language limits differ.
- Tests: `Invoke-Pester ./tests` (CI runs the same on `windows-latest`).

## Adding or taking over a package

Use the `choco-task-add-package` skill.

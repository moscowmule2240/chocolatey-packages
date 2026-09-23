---
name: choco-task-add-package
description: Use when adding a package to this Chocolatey packages repository or taking over a package already on the Chocolatey Community Repository, before choosing a package id or contacting anyone. Triggers - add a package, package an app for Chocolatey, adopt a stale package, 「パッケージを追加」「Chocolatey に登録」「パッケージを引き継ぐ」「メンテナ交代」.
---

# Add a package (entry point)

Classifies the request, routes it to the unit skill that holds the procedure, and ends
with the completion checklist. The rules in `AGENTS.md` apply throughout.

## Decide before starting

- The software, and whether upstream ships a Windows build. Without one there is nothing
  to package: tell the person and stop.
- The package id (section 1) and the route (section 2).

## 1. Classify by the software, not only by the id

An id can belong to different software: `zed` is the SpiceDB CLI; the Zed editor is
packaged as `zed-editor`.

1. Search by the software's name, both among approved packages and in the moderation
   queue, which the plain search leaves out:
   `https://community.chocolatey.org/packages?q=<name>` and
   `https://community.chocolatey.org/packages?q=<name>&moderatorQueue=true&moderationStatus=all-statuses`.
2. For each candidate, confirm from its description and project URL that it is the same
   software.
3. Check the id to be used:
   `curl -s -o /dev/null -w "%{http_code}\n" https://community.chocolatey.org/packages/<id>`
   — 404 is free, 200 is taken.

For an existing package, judge whether it is maintained:

- **Tracking upstream**: the latest approved version, or a version waiting in
  moderation, matches the latest upstream release or trails it by days.
- **Behind upstream**: upstream releases from weeks ago were neither approved nor
  submitted. A rejected submission counts as not submitted; the version history hides
  it, but `https://community.chocolatey.org/packages/<id>/<version>` returns 200.
- In between: check again a week later before deciding.
- Also note the maintainer's recent public activity and package repository, and the
  package page's comments: someone else, or the software's author, may already have
  asked to take it over.

## 2. Route

| Situation | Next |
| --- | --- |
| Maintained by this repository (maintainer `moscowmule2240`) | Not an addition: its `update-<id>.yml` keeps it current, and fixes follow `choco-create-package`'s rules. Stop. |
| Not packaged under any id, approved or in moderation | **REQUIRED SUB-SKILL:** `choco-create-package` |
| Packaged and tracking upstream | Do not take it over. If something needs fixing, offer its maintainer a pull request or an issue, drafted for the person to approve. Stop. |
| Packaged and behind upstream | **REQUIRED SUB-SKILL:** `choco-take-over-package`. It contacts the maintainer first and follows their answer, and uses `choco-create-package` for the build. |
| The wanted id belongs to different software, and the software is not packaged under any other id | Choose another id, then `choco-create-package` |

## 3. Completion checklist

If the maintainer chose a pull request, the package stays theirs: the pull request is the
whole outcome, and none of the items below apply.

- [ ] Approved on the community repository.
- [ ] The maintainer list is as intended; for a takeover, the previous maintainer's
      status is settled.
- [ ] The package's `update-<id>.yml` caller is on `main`, and a `workflow_dispatch` run
      shows `Preflight` and `Validate nuspec against community repository rules` green.
- [ ] `README.md` lists the package in the Packages table and the Automation table.
- [ ] The package's `README.md` says where upstream versions come from and records the
      Windows verification.
- [ ] For a takeover: `choco-take-over-package` step 9 is done — the removal pull request
      is open and the issue has a closing comment; their outcome depends on the previous
      maintainer. Skip it when the maintainer chose a pull request, when the package went
      to the software's author, or, for the parts that do not exist, when the Triage
      Process exception applied.

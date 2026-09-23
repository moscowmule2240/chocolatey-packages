---
name: choco-take-over-package
description: Use when a package on the Chocolatey Community Repository is behind upstream and its maintainer does not respond, when writing to a maintainer or to the Site Admins about maintainership, when an admin reply or a maintainer confirmation email arrives, or when a previous maintainer's automation still pushes. Triggers - 「引き継ぎ」「メンテナが反応しない」「Site Admins に連絡」「メンテナ交代」.
---

# Take over a package

Follows the Chocolatey Package Triage Process from first contact to handover. The rules
in `AGENTS.md` apply throughout. Reached without `choco-task-add-package`? Run its
section 1 first, to confirm the package is the same software and is behind upstream.

**Every outward action needs the person's go-ahead**: posting or closing an issue,
opening a pull request, forking, pushing, submitting a form, sending an email, posting on
Discord, and changing a package's maintainers. Draft messages for the person; forms and
emails are sent by the person.

## Procedure

1. **Investigate.**
   - The latest approved version against upstream; rejected submissions
     (`https://community.chocolatey.org/packages/<id>/<version>` returns 200 although
     the version history hides them) and their review logs — entries only from
     `chocolatey-ops` mean no person rejected the version.
   - The maintainer's package repository: last commit, and automation that still runs
     (AppVeyor build history, GitHub Actions runs).
   - The maintainer's recent public GitHub activity.
   - The package page's comments: the software's author may have asked for ownership.
   - If the maintainer is `needs_new_maintainer`, `dtgm` or `adgellida`, skip steps 3
     and 4: the Package Triage Process sends those packages straight to the Site Admins.
2. **Build and verify first**, with `choco-create-package` steps 1–3, so the request can
   point at a tested package.
3. **Contact the maintainer**: an issue in their package repository, and the form at
   `https://community.chocolatey.org/packages/<id>/ContactOwners` (tick "Send me a
   copy"). Include the evidence, a link to the prepared package, three options (a pull
   request, co-maintainership, a handover), and that the Package Triage Process follows
   after 7 days.
4. **Wait 7 days.** If the maintainer answers, follow their choice. A pull request:
   send it, with the person's go-ahead, and stop; the package stays theirs.
   Co-maintainership or a handover: once added, continue at step 6.
5. **Contact the Site Admins**, only if the maintainer has not answered, with the form on
   a version page, `https://community.chocolatey.org/packages/<id>/<version>/ContactAdmins`
   (at most 4,000 characters; tick "Send me a copy"): how and when the maintainer was
   contacted, with links; why the package needs attention; what is prepared. Send every
   request through the form, not as an email reply, including after a long silence. Do
   not ask about moderation timing.
6. **Replies.**
   - Added as maintainer: a confirmation email follows. Its link starts with `http://`;
     change it to `https://` before opening. Then publish with `choco-create-package`
     steps 4–6.
   - On hold because someone else offered first: after about two weeks with no visible
     progress (maintainer list, submissions), ask again through the form with that
     evidence.
   - No reply: after about two weeks, send the request again through the form as a
     follow-up, then ask in Discord (below).
7. **A rejected version blocks its number.** Pushing it returns 409 while the OData feed
   returns 404 for it. If upstream has a newer version, push that instead: a new number
   is not blocked. To ship the blocked version itself, ask through the form for it to be
   moved back to `submitted`, quoting the rejection notice ("we can move it back into a
   submitted status"), then push the corrected build under the same version. The 20 + 15
   day moderation timer runs from then.
8. **The previous maintainer.** Co-maintainers can remove each other on the site; no
   admin is needed. Propose removing them to the person when there is a mechanical reason
   — their automation still pushes the old build — or, once the takeover has settled,
   to make the list match who maintains the package.
   Measure a risk before giving it as the reason.
9. **Clean up the previous repository.** Fork it; clone the fork where the git identity
   and commit signing of this repository apply; remove the package and any automation
   that only served it; open a pull request. Then comment on the issue with the new
   location and close it.
10. **If the software's author is involved**, the Site Admins may prefer them. Be ready
    to hand the package over or share it.

## One package per contact

Each package needs its own maintainer contact and its own 7 days. Never add a package to
a Site Admins request unless its own maintainer contact is at least 7 days old — not
even when the same maintainer's other package is already before the admins. Start that
contact today; its 7 days run alongside the other request. The only exception is the
maintainers named in step 1.

## Discord

`#community-maintainers` in the Chocolatey Community Hub is for process questions only,
after two to three weeks without a reply. Never ask for a package to be moderated
(server rule 4a); post in one channel only.

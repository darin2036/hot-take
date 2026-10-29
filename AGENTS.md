# Project invariants

- Preserve local recording without authentication.
- Original code and documentation use MIT.
- Keep recording ownership in a document, never the service worker.
- Commit media chunks and metadata transactionally; bound write backlog.
- Do not add telemetry, hosted media infrastructure, or remote executable code.
- Do not claim native capture, device, cloud-storage, or store validation from synthetic tests.
- Cloud integration is future work: only the narrowest file-limited scope, account-bound resumable jobs, no automatic public sharing.
- Cleanup must be opt-in and app-file-only. Never permanently delete cloud-storage files.
- Preserve user changes and run focused tests plus the release build.

# Keep Help and the change log current

- Any change to what the Mac app does or how it looks to a person (a feature, control, menu item, shortcut, setting, default, permission, limit or fix) must update `mac/Resources/Help.md` in the same change. That file is Help ▸ Hot Take Help; each `## ` heading is a topic. Write for someone using the app. Add a topic for a new feature, edit the topic for a changed one, and remove text for anything taken out. Also keep `mac/README.md` accurate.
- Every change must add a short bullet in `CHANGELOG.md` under the newest version and build section (the next build) as the work is done, not at the end, in the matching category: `### Added`, `### Changed`, `### Fixed` (or `### Removed`, `### Security`). One line, plain words, what changed for a person; organized by version and build number, never by pull request, with no helper text and no "fix:" prefixes. Never leave a user-visible change unlogged. The app bundles both files (`mac/scripts/bundle.sh`), so What's New and Help show them.
- Do not claim a Help or changelog statement is verified on a real Mac unless it was; follow the compatibility notes.

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
- Every change must add a bullet to the current pull request's section under `## Unreleased` in `CHANGELOG.md` as the work is done, not at the end. Say what changed for people, mark fixes with `fix`, and never leave a user-visible change unlogged. If no pull request section exists yet, add one. The app bundles both files (`mac/scripts/bundle.sh`), so What's New and Help show them.
- Do not claim a Help or changelog statement is verified on a real Mac unless it was; follow the compatibility notes.

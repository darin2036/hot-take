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

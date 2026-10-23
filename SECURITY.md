# Security

Hot Take is a 0.1 pre-release and has not had an independent security audit. Only the latest source is supported.

## Reporting a vulnerability

Please do **not** post recordings, credentials or exploit details in a public issue. Use GitHub's **Report a vulnerability** (private vulnerability reporting) on this repository. If that is not available, open an issue asking for a private contact channel, without any details of the problem.

> Maintainer task before publishing: enable private vulnerability reporting in the repository settings.

## What to know about the design

- **Mac app:** recordings, captions, notes and click positions are plain files in `~/Movies/Hot Take/` (or the folder you chose). They are not encrypted by the app; protect them with FileVault and your account. The app refuses web requests and has no telemetry. Click positions (where and when you clicked, never what you clicked on or typed) are stored beside the recording. Speech recognition and writing use the system's on-device frameworks.
- **browser extension and web app:** recordings live in the browser's IndexedDB without extra encryption. Scripts served from the same origin, and anyone with access to the browser profile, can read them, so self-host on a dedicated origin. The extension has no host permissions, content scripts, cloud tokens or external messaging.
- **Permissions:** Screen Recording and Microphone on the Mac, and the browser's own prompts, are requested only when needed.

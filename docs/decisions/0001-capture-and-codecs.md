# ADR 0001 — Visible recorder and local WebM preview

Status: accepted for 0.1 preview; broader release gated.

Use one visible recorder page for extension and static hosting. Invoke the source chooser in its click handler. Avoid popup-owned streams, offscreen assumptions, and background-worker recording. Web Locks serialize media ownership per origin/profile.

Prefer feature-detected WebM VP8/Opus, then VP9/Opus, then browser WebM defaults. The actual recorder MIME type is persisted. Files keep their real `.webm` suffix. Synthetic headless browser playback passed; neither native capture nor cloud-storage compatibility has been established. Finite duration/seek metadata remains a gate. No remuxer or transcoder is bundled.

Optional webcam uses canvas and therefore needs visible-window/background performance measurement. Without webcam, encode the display track directly.

References consulted during implementation:
- https://developer.chrome.com/docs/extensions/how-to/web-platform/screen-capture
- https://developer.mozilla.org/en-US/docs/Web/API/MediaRecorder/dataavailable_event

These sources explain document ownership and final data events; they do not prove our device compatibility.

# Changelog

## 0.1.0 (pre-release)

First public source release. See [docs/compatibility.md](docs/compatibility.md) for what has and has not been verified.

- **Mac app:** screen, window and area recording to MP4 with microphone, size and audio choices; on-device captions, titles, summaries and suggested edits; a library with folders, emoji folder icons and versions nested under their original; Watch, Transcript and Info views; a Studio with splice and trim, text, captions, music, voiceover, a styled window background and auto zoom on clicks; compression and MP4, MOV and WebM export.
- **browser extension and web app:** local screen recording with optional microphone and webcam, IndexedDB storage with recovery, a library, and a basic editor.
- Local only: no accounts, telemetry, hosted media or remote code. Cloud upload and sharing are not implemented.
- **Mac app:** Save Project in the Studio writes a `.hottake` file (recording, edit and audio in one file) that a teammate opens from File ▸ Open Hot Take File… or by double-click; see [docs/hottake-file.md](docs/hottake-file.md).
- **Mac app:** Splice with the Audio track selected cuts the recording's sound on its own (remove a part to leave silence, Follow Video to undo); with nothing selected it still cuts video and sound together, and the Audio row now shows the break.
- **Mac app:** the record sheet shows the system's Mic Mode under the microphone and a **Microphone Modes…** button that opens the system menu, with a nudge toward Voice Isolation. The app can read the mode but only the person can change it.

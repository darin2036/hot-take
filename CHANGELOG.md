# Changelog

All notable changes to Hot Take are listed here, newest first, in the style of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/). A build number is the commit count at the time the app was bundled; it is shown beside the version in About and What's New. See [docs/compatibility.md](docs/compatibility.md) for what has and has not been verified.

## [Unreleased]

Builds 2 and later.

### Current pull request: launch welcome

- **Mac app:** redesigned the launch welcome with a midnight violet backdrop, flowing light trails around the flame icon, larger type and a visible skip hint. Reduce Motion shows a still composition.

### Added

- **Mac app:** shortcuts that work in any app: start/stop, pause, screenshot, and a take for an agent (⌃⌥⌘R, P, S and A by default, changeable in Settings).
- **Mac app:** Quick Record starts the screen used last with your last settings, no sheet.
- **Mac app:** screenshots of a screen, window or area, saved as PNG into the library folder.
- **Mac app:** camera-only takes (camera and microphone, no screen).
- **Mac app:** a floating speaker-notes window that is never in a recording, and an option to leave Notification Center out of captures.
- **Mac app:** record for an agent. A **For an agent** checkbox beside Start recording (or **Quick Take for Agent** in the menu bar, or **For Agent** on a take's Watch page) turns a take into a request a coding agent can act on: what you said beside a picture of the screen at each click with a ring where you clicked, a full transcript, and, with on-device intelligence, a goal and steps read from your narration. It is saved as `PROMPT.md` and PNGs in a hidden folder beside the take and copied with full picture paths, ready to paste into Claude Code, Codex or Cursor. Made on this Mac; nothing is uploaded. Visited links and app names are not recorded.
- **Mac app:** the Studio's **Mark** tool draws arrows, boxes and blurred regions, with handles to drag, and rings each click noted while recording. Marks follow the picture through a zoom or backdrop and ripple with cuts.
- **Mac app:** join recordings into a new take (clicks carry over), import MP4, MOV and M4V videos (File ▸ Import Video, or drop them on the library), playback speed 0.5× to 2×, choose a take's thumbnail, save a GIF of a stretch, and save a picture at each click.
- **Mac app:** chapters. They appear as headings inside the Transcript tab, are found on-device from the transcript's wording and pauses, and can be renamed, moved, added at any line or deleted. **Copy Timestamps** gives a `0:00 Title` list for a video description. The Studio's ruler shows them as markers, the Watch page has a **Chapters** menu to jump between them, and a saved copy keeps them, moved to where the same parts now begin. Chapters are kept in the take's `.json` (and travel in a `.hottake` file). On by default (Settings ▸ Processing ▸ **Find chapters in transcripts**).
- **Mac app:** the Transcript tab has a **Translate** menu that translates on this Mac with the system's Translation framework (the first use of a language may ask the system to download it). **Save … Captions…** writes a `.vtt` in that language, and the Studio's Captions popover can draw captions in a translated language. Translations are dropped when the transcript is corrected or remade.
- **Mac app:** each launch opens with an illuminated welcome, the logo and "What's your Hot Take?", then fades into the library. A click or key press skips it, Reduce Motion holds the artwork and words still, and it can be turned off in Settings ▸ Library.
- **Mac app:** Edit ▸ Find in Transcript (⌘F, ⌘G, ⇧⌘G) tints matching lines. A line can be corrected from its context menu and saved with a check mark.
- **Mac app:** Save Project in the Studio writes a `.hottake` file (recording, edit and audio in one file) that a teammate opens from File ▸ Open Hot Take File… or by double-click; see [docs/hottake-file.md](docs/hottake-file.md).
- **Mac app:** the Studio autosaves your edit to a hidden draft beside the take and restores it when you reopen the take. **Save Copy** and **Discard Edits** remove it.
- **Mac app:** Settings ▸ Recording has a microphone menu and the same Mic Mode row as the record sheet, with an **Open Mic Settings** button (the camera's is **Open Camera Settings**). While the record sheet or that pane is showing, Hot Take holds the microphone open without recording so the system's Mic Modes menu is available, and shows the mode macOS is really applying. The app can read the mode but only you can change it.
- **Mac app:** Help ▸ What's New shows this change log.

### Changed

- **Mac app:** Share in the Studio sends the current edited version, not the original file.
- **Mac app:** the separate Edit tab is gone; trimming and splicing happen in the Studio.
- **Mac app:** Splice with the Audio track selected cuts the recording's sound on its own (Follow Video to undo); with nothing selected it still cuts video and sound together.
- **Mac app:** captions in Chinese and Japanese wrap at a line length instead of running on as one line.
- **Mac app:** **Help ▸ Hot Take Help** (⌘?) opens a searchable help center with a topic for each part of the app (recording, shortcuts, the library, the Studio, saving, permissions, troubleshooting). Its text is `mac/Resources/Help.md`, bundled into the app, and `AGENTS.md` now requires every user-visible change to update it and the change log.
- **Mac app:** **Help ▸ What's New** shows this change log inside the app.
- **Mac app:** each build is numbered by its commit count, because the system caches icons by bundle ID and version and a fixed version kept showing an old icon in Control Center. Signing requirements, and so permissions, do not include the version.
- `mac/scripts/bundle.sh` clears stale Screen Recording, Microphone and Camera grants when the signing identity changes, uses the Apple Development certificate when there is one (`RELAYTAKE_SIGN_IDENTITY` overrides it), and falls back to an ad-hoc signature, with a warning that the Screen Recording grant will not survive rebuilds, when there is none.

### Fixed

- **Mac app:** fix: titles, summaries, tags, notes, the agent request and suggested cuts now use a whole long recording, not just its start (and end). The model reads it in pieces and the results are merged, on this Mac.
- **Mac app:** the buttons above a recording on the Watch page (Chapters, speed, Pictures, For Agent, Info, Trash) no longer crowd or cut off their names; in a narrow window they shrink to icons, then move below the title.
- **Mac app:** a recording whose picture ends before its audio no longer fails Save Copy, Share or Export with "No frame to draw on"; the last frame is held.
- **Mac app:** the camera now starts before the screen, so the camera bubble is in the video from the first frame; the Studio trims the camera's early footage. If the screen fails to start, the camera is stopped and its file removed.

## [0.1.0] - 2026-10-22

First public source release (build 1).

### Added

- **Mac app:** screen, window and area recording to MP4 with microphone, size and audio choices; on-device captions, titles, summaries and suggested edits; a library with folders, emoji folder icons and versions nested under their original; Watch, Transcript and Info views; a Studio with splice and trim, text, captions, music, voiceover, a styled window background and auto zoom on clicks; compression and MP4, MOV and WebM export.
- **Browser extension and web app:** local screen recording with optional microphone and webcam, IndexedDB storage with recovery, a library, and a basic editor.
- Local only: no accounts, telemetry, hosted media or remote code. Cloud upload and sharing are not implemented.

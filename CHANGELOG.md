# Changelog

All notable changes to Hot Take, newest first. See [docs/compatibility.md](docs/compatibility.md) for what has been verified.

## 0.1.0 (build 2)

### Added

**Recording**
- Countdown tones and an end-of-take chime, with a switch in Settings to turn recording sounds off.
- Rewind while recording: goes back 10 seconds and pauses so you can say it again (Record ▸ Rewind 10 Seconds, or ⌃⌥⌘W). Not available on camera-only takes.
- Shortcuts that work in any app: start/stop, pause, screenshot and a take for an agent (⌃⌥⌘R, P, S, A; changeable in Settings).
- Quick Record starts the last screen with your last settings, no sheet.
- Screenshots of a screen, window or area, saved as PNG in the library folder.
- Camera-only takes.
- Floating speaker-notes window that never appears in a recording, and an option to leave Notification Center out of captures.
- Microphone menu and Mic Mode in Settings ▸ Recording, with buttons to open the Mic and Camera settings.

**For agents and bug reports**
- **For an agent** turns a take into a request for Claude Code, Codex or Cursor: your narration beside a picture of each click, a transcript and, with on-device intelligence, a goal and steps. Saved as `PROMPT.md` and copied ready to paste.
- **Bug Report** on the Watch page drafts a ticket (title, summary, steps with pictures, expected and actual) to copy as Markdown, Jira, Slack or plain text.

**Studio**
- **Transcript** panel: select lines and press Delete to cut the video under them; **Bring Back** restores them.
- **Tighten** removes long pauses and filler words ("um", "uh", "er", "ah", "hmm") in one undoable step. English only.
- **Mark** tool: arrows, boxes and blurred regions, plus rings at each recorded click.
- **Find Sensitive Info…** finds emails, phone numbers, addresses, card and ID numbers, keys, tokens, passwords and words you list, and lets you choose which to blur. Off until you start it; runs on this Mac.
- Autosaved drafts, restored when you reopen the take.
- Save Project writes a `.hottake` file (recording, edit and audio together) that teammates open from File ▸ Open Hot Take File… or by double-click. See [docs/hottake-file.md](docs/hottake-file.md).
- Join recordings, import MP4/MOV/M4V (File ▸ Import Video or drop on the library), playback speed 0.5×–2×, choose a thumbnail, save a GIF of a stretch, and save a picture at each click.

**Transcript, chapters and summaries**
- Chapters are found on-device, shown as headings in the Transcript tab, and can be renamed, moved, added or deleted. **Copy Timestamps** gives a `0:00 Title` list. MP4 and MOV exports carry them (WebM does not yet).
- **Translate** menu translates the transcript on this Mac; translated captions can be saved as `.vtt` or drawn in the Studio.
- **Summarize** on the Transcript tab and **Summarize with AI** on the Watch page write a summary from the whole transcript, with Undo.
- Find in Transcript (⌘F, ⌘G, ⇧⌘G) and line corrections from the context menu.

**App**
- Launch welcome with a flame-icon animation; click or press a key to skip. It can be turned off in Settings ▸ Library.
- Help ▸ Hot Take Help (⌘?), a searchable help center, and Help ▸ What's New, which shows this change log.
- File ▸ Export: video as MP4, MOV or WebM, and the transcript as Markdown.
- Menu bar reorganized: File, View, and new Record, Take and Studio menus.
- Resizable Info panel and Transcript divider (double-click resets; widths are remembered).

### Changed

- Share in the Studio sends the edited version, not the original.
- Save Copy moved to File ▸ Save Copy (⇧⌘S); it and Export use the Studio's Save Options.
- The Edit tab is gone; trim and splice in the Studio.
- Splice with the Audio track selected cuts sound only; with nothing selected it cuts both.
- Transcript **Remake** is now **Regenerate**.
- Info panel: file details are collapsed by default, with only **Show in Folder**.
- Chinese and Japanese captions wrap at a line length.
- Each build is numbered by its commit count so the system refreshes the app icon.
- `mac/scripts/bundle.sh` signs with the Apple Development certificate when there is one, and otherwise ad-hoc with a warning that Screen Recording permission will not survive rebuilds. It clears stale permissions when the signing identity changes.

### Fixed

- Titles, summaries, tags, notes, agent requests and suggested cuts now use a whole long recording, not just its start and end.
- File ▸ Export works with a recording selected in the library or open in Watch or Transcript.
- Splicing too close to an edge or another splice does nothing instead of showing a message.
- Watch page buttons no longer crowd or cut off in narrow windows.
- A recording whose picture ends before its audio no longer fails Save Copy, Share or Export.
- The camera starts before the screen, so its bubble is in the first frame. If the screen fails to start, the camera is stopped and its file removed.
- The Info panel saves only the fields you edited, so it no longer overwrites a newer summary.
- Cutting several overlapping Tighten suggestions at once no longer cuts too much.
- The Info button on the Watch page uses the standard ⓘ icon.
- Removed the hint line along the bottom of the Studio.

## 0.1.0 (build 1) - 2026-10-22

### Added

- **Mac app:** screen, window and area recording to MP4 with microphone, size and audio choices; on-device captions, titles, summaries and suggested edits; a library with folders, emoji folder icons and versions nested under their original; Watch, Transcript and Info views; a Studio with splice and trim, text, captions, music, voiceover, a styled window background and auto zoom on clicks; compression and MP4, MOV and WebM export.
- **Browser extension and web app:** local screen recording with optional microphone and webcam, IndexedDB storage with recovery, a library, and a basic editor.
- Local only: no accounts, telemetry, hosted media or remote code. Cloud upload and sharing are not implemented.

# Changelog

All notable changes to Hot Take are listed here, newest first, in the style of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/). A build number is the commit count at the time the app was bundled; it is shown beside the version in About and What's New. See [docs/compatibility.md](docs/compatibility.md) for what has and has not been verified.

## [Unreleased]

Builds 2 and later.

### Current pull request: launch welcome

- **Mac app:** **Find Sensitive Info…** in the Studio's Mark popover looks through a recording for email addresses, phone numbers, addresses, card and ID numbers, keys, tokens, passwords and words you list, and lets you choose which to blur. It is off until you start it, shows a progress bar with Stop, runs on this Mac only, and adds ordinary blurs you can edit or undo. It can miss small or blurry text.
- **Mac app:** **Rewind** while recording. The control bar's Rewind button (also Record ▸ Rewind 10 Seconds, and ⌃⌥⌘W from any app, changeable in Settings) goes back 10 seconds and pauses, so you can say it again; Resume carries on from there. The footage you rewound over, your camera for it and its clicks are thrown away, and it can be pressed again to go back further. It is not offered on a camera-only take.
- **Mac app:** MP4 and MOV files saved or exported from the Studio (Save Copy, Export, Share, and File ▸ Export of a recording) carry the recording's chapters, so QuickTime Player and most players show a chapter list and jump to each one. WebM files do not carry chapters yet.
- **Mac app:** fix: the Info button on the Watch page uses the standard info icon (ⓘ) instead of a sidebar icon, filled while the panel is open.

- **Mac app:** fix: File ▸ Export now works with one recording selected in the library or open in Watch or Transcript, as well as the current Studio edit. Removed the explanatory heading from the Export menu.

- **Mac app:** sped up the welcome from 5.8 to 3 seconds, with earlier title reveals and a half-second fade when skipped.

- **Mac app:** the Info panel beside the video can be resized by dragging the bar between them (double-click resets), and its width is remembered.
- **Mac app:** the Transcript tab's divider between the video and the transcript can be dragged to resize them (double-click resets), and the width is remembered.
- **Mac app:** a **Summarize** button on the Transcript tab writes a summary of the whole transcript (long recordings are read in parts) and shows it in a card above the lines, with **Copy**, **Hide** and **Undo**. It is the same summary as on the Watch page.
- **Mac app:** a **Summarize with AI** button on the Watch page's Summary writes the summary from the whole transcript with the on-device model, with **Undo**. Nothing is uploaded.
- **Mac app:** fix: the Info panel saves only the fields you edited, so it no longer writes an old summary back over a new one.
- **Mac app:** the menu bar now holds the app's actions in the usual places: File (new take, new folder, open, open recent, import, save project, show in Finder), View (back to library, info panel, refresh), and new **Record**, **Take** and **Studio** menus. The old scattered File items moved into one group; New Take, Splice and the Info panel shortcuts now belong to the menus.
- **Mac app:** fix: splicing where it cannot be done (too close to an edge or another splice) no longer pops up a message; it simply does nothing.
- **Mac app:** **Save Copy** moved out of the Studio's top bar into **File ▸ Save Copy** (⇧⌘S). It, and File ▸ Export, use the Studio's Save Options.
- **Mac app:** a **File ▸ Export** menu: **MP4, MOV or WebM Video…** saves the Studio's edited video, and **Transcript as Markdown…** saves a take's transcript (with summary, tags and chapter headings) as a `.md` file.
- **Mac app:** removed the Apple Intelligence summary callout from the welcome and its added About credit.

- **Mac app:** a **Bug Report** button on the Watch page drafts a ticket for a person to paste into Jira, Slack, GitHub or a service desk: a title, summary, steps to reproduce with a picture on each step, expected and actual, all editable. With on-device intelligence it is written from your narration (only what you said); without it each step starts as what you said at that click. Copy it as Markdown, Jira, Slack or plain text, and drag the pictures out to attach them. Nothing is uploaded. The draft is kept in a hidden folder beside the take and reopens with your edits.
- **Mac app:** redesigned the launch welcome with a midnight violet backdrop, flowing light trails around the flame icon, larger type and a visible skip hint. Reduce Motion shows a still composition.

### Current pull request: edit by transcript and filler words

- **Mac app:** the Studio's Tighten is now one **Tighten** button, "Removes long pauses and filler words", with no settings or help text. It cuts every pause of 2 seconds or more and every filler word ("um", "uh", "er", "ah", "hmm") in one undoable step and says how many it removed. The pause-length choice, the filler checkbox and the review step for restarts are gone.
- **Mac app:** the Studio has a **Transcript** panel beside the preview. Select lines and press Delete (or **Cut Lines**) to cut the video under them, and **Bring Back** puts cut lines back. Cuts ripple and undo like any other.
- **Mac app:** **Tighten** in the Studio can find filler words ("um", "uh", "er", "ah", "hmm") from each word's timing, with **Cut All Fillers**. It always listens with SpeechTranscriber, because the classic dictation model drops these sounds. English only, on this Mac.
- **Mac app:** fix: cutting several Tighten suggestions at once no longer cuts too much when two of them overlap.

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

- **Mac app:** the transcript's **Remake** button is now **Regenerate**, and its confirmation says the AI built into your Mac does the work and that nothing leaves the Mac.
- **Mac app:** in the Info panel, the File details now sit in a section that stays collapsed until you open it, with only **Show in Folder**. **Copy Path**, **Make/Remake Captions** and the captions note are gone from it (captions are made from the Transcript).
- **Mac app:** Share in the Studio sends the current edited version, not the original file.
- **Mac app:** the separate Edit tab is gone; trimming and splicing happen in the Studio.
- **Mac app:** Splice with the Audio track selected cuts the recording's sound on its own (Follow Video to undo); with nothing selected it still cuts video and sound together.
- **Mac app:** captions in Chinese and Japanese wrap at a line length instead of running on as one line.
- **Mac app:** **Help ▸ Hot Take Help** (⌘?) opens a searchable help center with a topic for each part of the app (recording, shortcuts, the library, the Studio, saving, permissions, troubleshooting). Its text is `mac/Resources/Help.md`, bundled into the app, and `AGENTS.md` now requires every user-visible change to update it and the change log.
- **Mac app:** **Help ▸ What's New** shows this change log inside the app.
- **Mac app:** each build is numbered by its commit count, because the system caches icons by bundle ID and version and a fixed version kept showing an old icon in Control Center. Signing requirements, and so permissions, do not include the version.
- `mac/scripts/bundle.sh` clears stale Screen Recording, Microphone and Camera grants when the signing identity changes, uses the Apple Development certificate when there is one (`RELAYTAKE_SIGN_IDENTITY` overrides it), and falls back to an ad-hoc signature, with a warning that the Screen Recording grant will not survive rebuilds, when there is none.

### Fixed

- **Mac app:** removed the hint line along the bottom of the Studio; the bar there now appears only when something is selected.
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

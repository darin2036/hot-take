# Validation record — October 20, 2026

## Actually run

- Node 24.18.0, npm 11.16.0 on a Mac.
- TypeScript type check and Vite production build.
- Five Vitest tests: chunk order/atomic metadata and late-write rejection; interrupted bytes and deletion isolation; missing-record rejection; paused time; filenames/container extensions.
- Build validation: MV3, incognito disabled, no additional extension or host permissions, no content scripts, no remote HTTP URLs in application JS/CSS.
- Playwright CLI, HeadlessChrome 156: synthetic 640×360 canvas replacing only the display-capture source. Real MediaRecorder, IndexedDB, video element, and download event exercised. Pause time stayed fixed; resume/stop saved; preview decoded video and advanced playback; `.webm` filename was correct; reload retained the take.
- Desktop screenshot inspected at 1280 pixels; narrow layout inspected at 390 pixels, with no horizontal overflow.

The first playback test raced asynchronous preview creation; waiting for the dialog fixed the test, and the full flow passed on rerun. This was a test synchronization issue, not claimed as a native-device pass.

## Not validated / release blockers

Native picker behavior, OS permissions, real mic/camera, mixed audio quality, source termination, multi-tab lock contention, low-disk fault injection, finite WebM duration and seeking in external players, long-session memory, background webcam frame cadence, and screen-reader operation are not yet validated. Windows/Linux and the previous stable browser release are untested. Chrome 116 is the manifest baseline, not a compatibility promise.

There is no cloud-storage client in this build. OAuth, native timestamp comments, recipient codecs/playback, organization policies, upload recovery, and retention are entirely pending. The original plan's future-dated or platform-specific statements are not treated as verified runtime evidence.

No release is suitable for claims of parity with hosted recorders or production-grade long recording until these gates are closed.

## Reproduce the synthetic browser check

`tests/browser-check.js` is a Playwright CLI `run-code` function, not a Vitest unit test. Run it against `npm run dev` in a **disposable browser profile**; it deletes that profile/origin's existing test recordings before running. It replaces the screen source with a synthetic canvas, then exercises the actual encoder, storage, UI, preview and download. It deliberately does not bypass OS prompts in a real user profile. The CLI package is external developer tooling and is not shipped with the app.

## Extension popup validation — October 20, 2026

- Loaded the actual unpacked production MV3 build in Chrome for Testing 151 in a disposable persistent profile. the browser's extension manager confirmed Hot Take enabled.
- Opened the packaged popup document on its chrome-extension origin; New recording created a recorder window through the real extension API.
- Injected only a synthetic canvas display source. Real MediaRecorder, IndexedDB, BroadcastChannel, extension context discovery, tab/window APIs, and video preview ran.
- Popup pause froze the recorder timer; closing/reopening the popup restored Resume; resume continued capture; closing it again did not interrupt capture.
- Stop saved the take; recent-take navigation opened the library preview and decoded 640×360 video with advancing playback. Reload preserved the recording.
- Reusing an idle recorder focused the existing context and applied changed microphone selection without creating another recorder.
- Nine unit tests pass, including malformed-message rejection, owner-bound command acknowledgements, and missing-owner timeout. Typecheck/build/manifest validation pass.
- Popup and recorder screenshots inspected; narrow popup layout uses the shared button typography.

This uses the actual extension pages and APIs, but opening the toolbar bubble with the physical browser toolbar button and native source/device prompts still requires manual validation. No worker restart test applies: this version has no worker.

`tests/extension-check.js` is a Playwright CLI run-code function for a disposable persistent Chrome for Testing profile with the built extension loaded, starting at chrome://extensions. It discovers Hot Take's generated extension ID. Keep the profile disposable: synthetic takes are created during this check.

Final popup layout verified at 380×600 with no horizontal overflow and 14px primary-button text matching the shared scale. The browser applies a smaller body font to extension pages by default; explicit body inheritance now neutralizes that rule.

## Lucide icon update

Installed pinned lucide-static 1.60.0; selected SVGs are bundled locally. Lucide/Feather notices ship in the release ZIP. Nine tests, typecheck, production build, and synthetic browser recording/pause/resume/preview/download/reload checks passed after replacement. Popup visual inspection at 380×600 confirmed consistent SVGs, decorative aria-hidden attributes, and no horizontal overflow. Build validation permits the SVG XML namespace identifier, which is not a network request.

## Basic editor validation

15 unit tests pass, including non-mutating range removal, trim across prior cuts, multiple cuts, and rejection of empty/invalid edits. Production build includes editor.html and validates the unchanged permission budget.

In a headless browser, generated a synthetic red/green/blue video with a 440 Hz audio tone. Trimmed to three seconds, removed the middle second, exercised Undo, and saved a copy. Pixel sampling at 0.3 and 1.4 seconds confirmed red then blue (no green at those samples). Audio decoding measured approximately 1.98 seconds for the requested two-second output and a nonzero signal. Original metadata and bytes remained present. Selection handle synchronization, save cancellation without a leftover draft, and 390px layout also passed. This does not establish frame accuracy, lip sync on spoken recordings, long-file memory behavior, or actual browser-extension editor operation.

`tests/editor-check.js` reproduces the synthetic export check with Playwright CLI against the dev server. Use a disposable profile; it creates test recordings. Export uses the recording-owner lock to prevent concurrent capture/recovery from changing an in-progress copy.

### Countdown and floating controls

Synthetic browser checks verified 3–2–1 before encoding, restart from paused via the toolbar protocol, retained capture tracks, a fresh saved take with reset duration, and countdown cancellation without an empty library item. Document Picture-in-Picture opened successfully; floating Pause/Resume/Stop and closing/reopening controls were exercised. Native screen-picker/device capture and OS-level always-on-top behavior still need manual validation with the unpacked extension. The browser owns PiP placement and chrome; the ordinary extension toolbar popup cannot be pinned.

### Text overlays

Synthetic browser checks verified dragging, drag Undo, keyboard positioning after Undo, responsive layout, and exported text timing across a removed segment. Pixel samples of the re-encoded copy found text only inside its chosen source-time interval; original metadata was unchanged. Preview and export share the same canvas layout and drawing code.

### Audio editing

Synthetic browser tests exercise WAV import, added-track start offset, original-audio mute, export decoding and frequency checks, voiceover across cuts, cancellation, microphone-track cleanup, and narrow layout. Hardware microphone permission/device behavior still requires manual testing. Import is limited to 100 MB and decoded audio to 128 MB; supported formats depend on browser decoding. Real-time export still requires a visible tab.

## MP4-first recording — October 21, 2026

Recording now prefers MP4 (H.264/AAC) and falls back to WebM. Twenty unit tests (including the format preference order), typecheck, and the production build with manifest validation pass. In the browser pane of the desktop app, a 3-second synthetic canvas plus oscillator recording through `MediaRecorder` produced an `ftyp` MP4 that the browser decoded with a finite 2.97 s duration at 640×360. the browser writes fragmented MP4. Not validated: other desktop and mobile players, inline playback in chat and storage tools, scrubbing in external players, the editor's MP4 re-encode on real recordings, and the Playwright checks against MP4 output. The Playwright helper scripts still generate WebM fixtures, which the app still accepts.

## Mac companion app — October 21, 2026

`mac/` builds with the Swift command line tools on macOS 27 (Swift 6.3). Eight core tests pass (captions, naming, metadata, summary parsing). `Hot Take --process` on a synthetic text-to-speech clip produced timed on-device Speech segments, a `.vtt`, and a Foundation Models title and summary. Real screen capture, permission flows, microphone/system audio, long recordings and playback of its MP4s elsewhere were not run; they need a person at the machine.

### Mac library and editor — October 21, 2026

Added a Library window (thumbnails, player, summary, click-to-seek transcript, rename, move to Trash) and a trim/cut editor ported from the extension's edit model. Sixteen Swift tests pass, covering the cut list (remove, trim across cuts, invalid ranges, undo/reset, time mapping) and library folder logic. The export path ran on a generated H.264+AAC video: removing 3–6 s of 11 s gave 8.00 s with one video and one audio track, and sampled frames showed the correct section removed. The windows were built but not viewed; the player, timeline dragging, Preview edit, Save copy from the UI, Trash, and files with separate microphone and system-audio tracks were not exercised.

### Mac capture sources — October 21, 2026

New Take now offers entire screen, window/app (system content picker) and a dragged area. The coordinate flip and even-pixel sizing for areas are unit tested (18 Swift tests pass); the chooser, picker, overlay, multi-display behavior, and capture of each target were built but not exercised on screen. If the recorded window closes the take is stopped and saved; that path is untested.

### Mac folders, metadata, multi-select, Settings — October 21, 2026

Added a folder sidebar, recursive library scan, folder create/rename/trash, moving takes (files move together and avoid name clashes), tags and notes in the sidecar JSON (older sidecars still load), an Info tab, multi-select with bulk Move/Trash, and a tabbed native Settings window. Thirty Swift tests pass, including folder scan/tree/create/rename/move and metadata round trips. Through accessibility, the Settings window opened with ⌘, and each of its four tabs resized to its content with no scroll area; the library window title showed the recording count. The sidebar, drag and drop, the Info tab's autosave, selection mode and bulk Trash were built but not exercised on screen (accessibility returned an empty window when tried). Bulk Trash was deliberately not run against real recordings.

### Mac right-click menus and detail layout — October 21, 2026

Added right-click menus for recordings, the sidebar and empty library space, no-bounce scrolling when content fits, and a single centered detail column with the Details/Info/Edit picker centered under the video. Thirty Swift tests pass. Through accessibility the library window showed a split view with a sidebar outline and, at 713 pt wide with the sidebar open, a list-mode detail pane. The menus, the centered layout, and opening a recording from list mode were not verified: the app would not report as frontmost, so synthetic clicks were inconclusive and are not evidence either way.

### Mac file-manager-style selection — October 21, 2026

Replaced the select mode with file-manager-style selection. The rules (click, ⌘-click, ⇧-click ranges, arrow keys with ⇧-extend, select all, box selection, pruning) live in RelaytakeCore with five tests; 35 Swift tests pass. The grid draws a selection box over empty space, double-click opens, Delete confirms before trashing, and dragged recordings carry the whole selection to a sidebar folder. The list uses SwiftUI's native multi-selection. None of the pointer or keyboard behavior was exercised on screen; the build and unit tests are the only evidence.

### Mac model-written fields and suggested edits — October 21, 2026

Added per-field and *Generate All* writing for the Info tab (title, summary, tags, notes) and a Suggested edits panel. 46 Swift tests pass, covering reply cleanup, silence detection (including a threshold off-by-one the tests caught), transcript pauses, and parsing/validating the model's cut recommendations.

Run on this Mac (macOS 27, on-device intelligence) through the bundled app on synthetic text-to-speech clips: measured silence found two deliberately inserted gaps (4 s and 3 s) at the right times. The model's first cut prompt was poor: on a clean clip it recommended cutting a greeting and the conclusion as "casual" and "redundant". After tightening the prompt (default answer NONE; cuts only for an immediate repeat, an abandoned restart, or filler-only lines), the clean clip produced no recommendations and a messy clip with "Um… you know", a repeated sentence and "wait, let me start over" produced two correct recommendations. All four fields generated sensible text. That is two small synthetic clips, not an evaluation: the model can still be wrong, which is why each suggestion is a proposal. The panel and buttons were built but not exercised on screen. The model's wording "review the pool" came from the speech recognizer mishearing "pull request".

### Mac Studio editor — October 21, 2026

Added a fixed-layout Studio (Video, Text, Audio, Music, Voiceover tracks) with undo/redo, text overlays, background music, a recorded voiceover and Save Copy. The rules live in RelaytakeCore with tests (ripple through cuts, a voiceover split by a cut, looping and fades, lanes, replace rules). The composer is tested by rendering generated files: after a 1 s cut a 6 s video came out 5 s; text was drawn at the top (not the bottom) only while it should show; music, muted original, looping and a voiceover placed at 3 s measured at the expected loudness at the expected times; the preview composition is exactly as long as the edit (74 Swift tests pass). A rendered frame showed correct text at both positions, in both styles, and gone after its end.

the system's Core Animation video tool (AVVideoCompositionCoreAnimationTool) returned blank white frames on this Mac even with only the video layer, so text is drawn by a custom compositor instead. The Studio's layout was inspected by rendering it offscreen (1000×700 and 560×500): it fits with no scrolling; the video player itself does not draw in that render. Not exercised on screen: dragging and resizing clips, dragging text on the preview, playback of the live preview, the voiceover recording (microphone), the Suggest Edits popover, and Save Copy from the interface.

### Mac playback modes — October 21, 2026

Added theater, pop-out and full-screen buttons (hover bar on the take's player and the Studio preview). An in-process check (`Hot Take --playback-check`) confirmed the pop-out window opens, floats above other windows and keeps the video's aspect ratio, that windows are tracked and closed by owner (without touching another owner's), and that leaving full screen closes the full-screen window. Theater and the button bar were rendered offscreen and inspected. Not exercised: actually entering full screen (it would take over the display), clicking the buttons with a pointer, the keyboard shortcuts, and pop-out/theater playback with real video, which does not draw in offscreen renders.

### Mac Studio replaces the Edit tab — October 21, 2026

The Edit tab and its workspace are gone: the Studio is the one editor. Save Copy gained a Save Options popover (keep original quality, or Small/Medium/Large/Custom; include audio) and Export to a file as MP4, MOV or WebM. The Studio renders text, music and voiceover once at full quality, then, if a smaller file or another format is wanted, passes that render to the existing compressor and exporter. "Make Captions" moved to the Info tab's File section. The voiceover can use any microphone (a capture session instead of the system default).

Verified by running the real code: every combination of original/small/medium, MP4/MOV, with and without audio, plus WebM, rendered a sample edit (a 1 s cut and text) from a 17 s clip; durations were 16 s, Small was 15 fps and Medium 24 fps, MOV and MP4 had the right containers, the silent copy had no audio track, WebM had a Matroska header, the text was still drawn after compression, and no staging folders were left behind. The library Save Copy path was run in both modes: a compression-only copy kept the title, tag, note and transcript; an edited copy got a new title, transcript and captions. `Pipeline.process` was changed to keep existing tags, notes and title (it used to rewrite the notes file), and Make Captions was confirmed to leave them intact. 75 Swift tests pass. Not exercised: recording from a chosen microphone (it would record the room), the Save Options popover and the microphone dropdown being clicked, and the Studio's other interactions already listed above.

### Mac Studio text styling and a hotkey fix — October 21, 2026

Text now has a full style: font family (the system font plus familiar families that are installed), bold, italic, a continuous size (with S/M/L/XL presets), any color (nine swatches plus the system color picker), and an optional box with its own color. A Style popover on the text bar edits it all; the bar keeps the text field, five quick swatches, the duration and delete. The saved video and the preview build the font from one function, so they match.

Bug fixed: the Studio's space (play/pause), delete (remove the selected clip) and escape handlers also fired while typing in the text field, so a backspace could delete the selected text clip. They now stand down whenever a text field is being edited. Verified by an in-app check that a text field being edited is detected and that detection ends when it is left; typing into the live window was not exercised. 81 Swift tests pass, including a render showing red italic text raises the red channel only while it shows and a white box behind black text brightens its area. The popover was rendered offscreen and inspected; clicking its controls was not exercised.

### Mac Settings spacing — October 21, 2026

Measured through accessibility in the live Settings window: the first section heading was 40 pt below the tab bar (20 pt of outer padding plus the grouped form's own 20 pt inset) with another 20 pt of padding at the bottom. The outer padding is gone and the form is nudged up, so the heading sits 8 pt under the tabs and the windows are 331, 226, 223 and 182 pt tall (Recording, Captions & Summary, Permissions, Library), each with its form ending at the window's bottom edge. SwiftUI has no setting for the grouped form's inset on a Mac, so the nudge is a negative top padding. Not exercised: the look in a different appearance (light mode) or with a larger text size.

### Mac speech layer shared with Plainspoken — October 21, 2026

Captions now come from the PlainspokenSpeech package (Plainspoken/Packages/PlainspokenSpeech): the system's two on-device engines, a language picker, vocabulary correction, model preparation with progress, a file transcriber that mixes every audio track, and a network guard. Hot Take's transcriber is a thin wrapper that reads Settings. The package has no dependencies, so Hot Take does not fetch or build WhisperKit; Whisper is deliberately not included.

Verified by running the real code. The package's 21 tests include the recognizer on speech made with the Mac's voice (ordered time-stamped segments, vocabulary, progress ending at 1, a two-track movie where both speakers appear, a file with no audio reporting an error, cancellation, the classic engine) plus the guard blocking a real web request. Plainspoken, switched onto the package with no change to its app code, produced output identical to its pre-refactor baseline on the same clip for both engines and with vocabulary. In the bundled Hot Take, `--network-check` confirmed web requests are refused, and the Settings (vocabulary, recognizer, language) changed the app's captions: without a vocabulary "pull request", "Jira" and "Rovo" were wrong; with one they were right.

The only real recording with audio (47.8 s) has no recognizable speech: the package harness, Plainspoken's harness and Hot Take's app path all returned zero segments, so it says nothing about speech quality. As a substitute, known speech was mixed over that recording's real audio: the newer engine heard all 24 spoken words, the classic engine 23, and no background sound was mistaken for speech; with vocabulary 11 of 11 key terms were right versus 8 of 11 without. That is synthetic speech over real background audio, not a person speaking, so a real check needs a recording with a real voice. Not measured: accents, long recordings, other languages, Whisper (not included). The package is a path dependency, so Plainspoken must be checked out beside this repository to build the Mac app.

### Record sheet, Transcript tab and Studio captions — October 21, 2026

The app stores recordings in `~/Movies/Hot Take`. A Mac that already has recordings in `~/Movies/Relaytake` keeps using that folder, so nothing moves and no recording is left behind. The bundle identifier, saved settings, the extension's stored data and lock/channel names, and the Swift module names are unchanged for the same reason. The Mac app is built as `build/Hot Take.app`.

The Mac record sheet now has a microphone menu, a file-size menu, a No audio box, previews of every open window, and screen previews sized to the real screens. The detail view has a Transcript tab, and the Studio can draw captions into the video in four styles. Right-click on the video offers Show in Folder, and the Info tab's File section has a Show in Folder button.

Verified: the 88 Swift tests pass, including captions following cuts and a saved video showing the caption box only while the line is spoken (brightness of the caption area at a time during the line against a time after it, with the area away from the caption unchanged), and the folder choice. Not verified: the record sheet's window previews and microphone choice with a real recording, and the new tabs on screen, unless listed below. Recording one browser tab is not possible with ScreenCaptureKit, so the sheet records the whole browser window.

### Emoji folder icons and the default Hot Takes folder — October 21, 2026

A folder's emoji is the start of its real folder name, so the file manager shows it and no extra file is needed. Verified by running the real app: a `🔥 Hot Takes` folder was created in the library and drawn with its emoji in the sidebar, the icon picker opened from the right-click menu, and choosing 🚀 renamed the folder on disk to `🚀 Hot Takes` (changed back afterward). The 93 Swift tests cover splitting and joining names, rename keeping the icon, setting and removing icons, and creating the default folder once without duplicates. Not verified: folders synced by cloud-storage tools or other tools that may normalize emoji names, and typing an emoji through the system emoji picker. New recordings still go to the top level unless a folder is open.

### Recording Hot Take itself — October 21, 2026

By default the app's own windows are left out of screen and area recordings, and its windows stay minimized while it records. A new *Show Hot Take in the recording* option (screen and area) keeps the app's windows on screen and in the video, and a Hot Take window chosen in Window or app is recorded too. Verified with a real 14-second recording of an external display on this Mac: a frame from the saved MP4 shows the Hot Take library window (folders, recordings, toolbar), and the menu-bar stop icon appeared while it ran. Limits: only windows open when recording starts are included, and the floating control bar is never in the video. Not verified: recording with microphone or computer audio in this mode, and the area mode.

### Background and Auto Zoom — October 21, 2026

Added to the Mac Studio: a styled backdrop behind the recording (with the window rounded, inset and shadowed) and zoom that follows recorded clicks, both applied in the Studio and drawn in on save. Clicks are noted while recording (position and time only) and stored in the take's `.json` beside the video.

Verified: 113 Swift tests, including real exports through the Studio's own renderer showing the backdrop color in the margin and the window in the middle, a zoom filling the corner only while it lasts and easing back, zoom without a backdrop keeping the video's size, and previews carrying the effects. The geometry, timing, click grouping, cut ripple and metadata round-trip are covered by unit tests. In the real app, a 74-second recording of an external display with three real clicks on the wallpaper saved those clicks at the right places (position matched where they were made, within a few thousandths of the screen) and the Studio generated a zoom block around them, previewed it zoomed toward that spot, and showed the backdrop with its presets, color, margin, corner and shadow controls.

Not verified: click positions for a *window* recording (the window-follows-moves path), clicks inside other windows while recording a single window, area recordings, a saved copy with a zoom made from that real recording played in another app, and long recordings. The zoom focus stays fixed for each zoom rather than following the pointer, and zoom looks soft at high magnification because the picture is enlarged, not re-captured. A window's own rounded corners come out of the capture as black corners, which the backdrop's rounded corners cover; with very small corner settings a sliver can show.

### Custom file-size estimate and draggable control bar — October 21, 2026

The estimate under *Custom* file size used the typed bitrate only, and the bitrate box applied a value only after Return, so changing the resolution or frame rate, or typing a bitrate, did not move it. Now the video bitrate has an Auto setting that follows resolution and frame rate (1080p at 24 fps gives 1600 kbps, the Medium preset), number boxes apply each digit as typed, and the estimate follows. Verified in the running app: with Custom chosen, typing a higher frame rate moved the estimate from about 12 to about 30 MB per minute with no Return. The estimate is still derived from the bitrate, so a mostly still screen usually saves smaller than it says.

The recording control bar can now be dragged. Verified with a real recording: dragging its grip moved the bar by the distance dragged and saved the new position. Not verified: the bar returning to the saved spot on the next recording, and dragging between displays.

### Flame icons and [ ] section marks in the Studio — October 22, 2026

All Hot Take icons now use the same white flame on the blue-violet tile: the Mac app icon, the menu bar (a monochrome flame that follows the menu bar's light or dark appearance), the browser extension icons, and the web favicon. `scripts/build-icons.py` rebuilds the app-icon, extension and favicon images from `artwork/hot-take-master.png`. The favicon is a raster image inside an SVG, not a vector drawing. The web build and its 20 tests pass; the app icon was built and bundled but not yet seen on screen, and the extension icons were not loaded in a browser.

Trimming and splicing live in the Studio's Video track: drag across it to pick a section to remove or keep. New: press `[` where a section starts and `]` where it ends (or use the [ and ] buttons beside the time), and the section is selected for Remove Section or Keep Only This; a lone mark shows as a flag on the track. Verified by rendering the Studio with both marks and with only a start mark (the flags, the selected section and its buttons all appear). The key presses themselves were not tried in the running app, and the mark logic has no automated test because it lives in the app layer; the cutting it triggers (remove and keep-only, with text, music and zooms following) is covered by the existing tests.

### Splice, parts and draggable edges in the Studio — October 22, 2026

Replaces the start/end marks added earlier the same day. **Splice** (button, S, or ⌘B) breaks the video at the playhead and removes nothing; parts between splices are chosen by clicking and removed with Delete, *Remove* or *Keep Only This*. A splice can be dragged to slide it (one part grows, its neighbor shrinks, the length stays), the ends of the video and the edges beside a removed part can be dragged to trim in (removing footage and moving later text, zooms and voiceover earlier) or out (bringing back footage that was removed, if any is left, and moving them later). Right-click offers Splice Here, Remove This Part and Remove Splice. `[` and `]` remove the video before or after the playhead within its part.

Verified: 128 Swift tests, including splitting and refusing splices too close to an edge, removing a part leaving a gap rather than a splice, sliding and merging splices, edges stopping at their neighbors and at the ends of the original, text and zooms following trims in both directions, and trim before/after. The Studio rendered with parts, a chosen part with edge grips and the Part N of M bar, and with a removed part leaving an orange gap marker. `Hot Take --splice-check Take.mp4` also drives the Studio's own model the way the gestures do, on a real recording: two splices keep the length, dragging one slides it as one undo step, clicking and deleting a part shortens the video, dragging the edge beside the gap brings footage back (and undo restores the gap), dragging the start in trims it, and `[` drops the video before the playhead. All ten steps pass. Not verified in the running app: the actual mouse gestures and hover cursor, the right-click menu, and the S and ⌘B keys. Splicing alone marks the project as edited even though the picture is unchanged.

### Info panel on Details and a tighter summary — October 22, 2026

The Info tab is gone. An **Info** button on a recording's Details page (⌥⌘I) slides the same editing panel in beside the video, which resizes to fit; it shows title, tags, summary, notes (each with its sparkle button) and the file details with no paging, and remembers whether it was open. The Details summary no longer pages: it shows the whole text at its natural height right under the video, clamped to eight lines with Show more when it is long, so there is no empty space beneath it. The one-line summary shown in the library list is unchanged.

Verified by running the real app on a recording with a summary: Details shows the video, then the summary directly under it; clicking Info slides the panel in and the video narrows. Not verified: long summaries (the 8-line clamp and Show more), very narrow windows with the panel open, and the ⌥⌘I shortcut. The panel's Generate and Make Captions buttons were not pressed in this change.

### Versions nested under their original in the library — October 22, 2026

Copies saved from the Studio are now grouped under the recording they were made from. The link is the copy's `derivedFrom` in its notes file, written when the copy is saved; older copies are recognized by "(edited)" or "(edited N)" in the name. Copies of copies belong to the same group. A group shows only its original (with a "N versions" pill) until opened, families sort by their newest member, and search lists every match. An original moved to another folder takes its versions with it; trashing an original leaves them standing alone.

Verified: 135 Swift tests (name recognition, ordering, collapsed and opened groups, chains, a missing or other-folder original, a recorded link overriding the name, and the link surviving a rewrite), and the real app on a library with one original and one saved copy: the original showed a "1 version" pill with the copy folded away, and opening it put the tinted copy right after the original with "Edited from" its original. Not verified: list view in a narrow window, the keyboard moving through opened versions, moving a family between folders, and a take renamed by a name clash while moving (that would break the name-based link).

### Watch tab — October 22, 2026

The recording page's first tab is **Watch**: Watch, Transcript, Studio. Earlier entries in this log call it Details. The saved preference for whether the Info panel is open keeps its old internal name, so nobody's choice is reset.

### About window — October 22, 2026

A proper About window replaces the standard system panel: version and build, the privacy promises, links to the source, issue tracker, MIT license and third-party notices, and a button that copies the version, system version and Mac model. It opens from the app menu and from the menu bar icon. Verified: it built, opened from the menu bar icon (its window appeared), and rendered offscreen with `--about-snapshot` showing all text and the four links fitting. Not verified: clicking the links (they point to `github.com/darin2036/hot-take`, which must exist) or the copy button.

### Window minimums and a floating folder list — October 22, 2026

The main window now has a minimum size that depends on what it is showing (680 pt wide for the library, 800 for a recording's Watch, Transcript and Studio pages, 840 with the Info panel open), and it grows to that size when you move to a page that needs more. 640 was tried first and the toolbar folded the Watch/Transcript/Studio tabs, New Take, Share and Settings into a ">>" menu, so the minimum for recording pages is set by the toolbar. The folder list no longer takes a fixed column: it floats over the page from the Folders button, and Pin docks it and widens the window by its 220 pt (unpinning gives the width back). Verified in the real app: floating list and Pin; the window growing from 900 to 1120 on pin and back to 900 on unpin; the library refusing to shrink below its minimum; and at the minimum width the Watch, Transcript and Studio pages and the Watch page with Info open each showed every toolbar control without clipping. Not verified: very small screens (the window is limited to the screen), moving the window between displays of different sizes, and dragging the pinned list's divider.

## Camera in the recording

The record sheet has a camera menu with a live preview and a button to the system's Video Effects panel. A recording with a camera keeps the screen recording and the camera file in a hidden `.hot-take-originals` folder beside the take, draws the bubble into the take itself, and lets the Studio move, resize, reshape or hide it. Verified with synthetic video: the bubble is absent before the camera's footage begins and after it ends, present between, follows cuts, and moves with the chosen corner; originals move, trash and round-trip with the take. Not verified: a real camera, the permission prompt, the system video effects, Continuity Camera, and how closely the measured start offset matches what you saw on screen (the Studio's Line up control corrects any drift by hand).

## Tighten

The Studio's Suggest Edits panel became **Tighten**: long pauses (1, 2 or 3 seconds, from the audio levels and the transcript's timing) and restarts (neighboring transcript lines compared by their words, with the on-device model asked only for ones the comparison missed) are drawn on the Video track, where each can be cut or kept by hovering, and all pauses can be cut at once. Verified: the word comparison with unit tests (repeated sentence, abandoned start, a changed word, punctuation, unrelated lines, short lines, and repeats far apart), the combining of the two sources, and the layout in an offscreen render with sample proposals. Not verified: accuracy of the pause and restart suggestions on real speech, the model's restart checks, and hovering and cutting from the markers with a real pointer.

## Hot Take file (`.hottake`) — October 27, 2026

Save Project in the Studio writes the take and its edit to one file; File ▸ Open Hot Take File… (or double-click) adds it to the library as a new take with the edit waiting in the Studio. Format in [hottake-file.md](hottake-file.md).

Verified: unit tests that write and read files with real data (3 MB blobs round-trip byte for byte, empty blobs, a file that is not ours, a cut-short file, a flipped byte inside a blob and inside the table of contents, a newer format version, replacing an existing file leaves no temporary files), and take-level tests (a take with an edit, captions-less takes, a damaged file leaving the library untouched, two imports never colliding, no sender folder names inside the file, and moving an imported take keeping its audio and repointing its draft). The app builds and the bundle's Info.plist, with the new document type, passes `plutil -lint`.

Not verified: the Save Project and Open File panels, double-clicking a file in Finder and the file icon, opening on a second Mac, large (multi-gigabyte) recordings and their progress display, and a recording with a presenter camera through a real round trip.

## Microphone mode in the record sheet — October 27, 2026

Under the microphone switch the sheet shows the Mac's Mic Mode for Hot Take (Standard, Voice Isolation or Wide Spectrum), a one-line hint, and a **Microphone Modes…** button that opens the system's Mic Modes menu. Hot Take cannot choose or force a mode; macOS only lets the person pick it and remembers the choice per app.

Verified: the app builds and the sheet draws with the new row (rendered with `--record-sheet-snapshot`, showing "Mic mode: Standard" on the test Mac).

Not verified: that the button opens the menu while nothing is recording, that Voice Isolation applies to microphone sound captured through ScreenCaptureKit (the recording path) and to voiceovers (a separate capture session), that the row updates after the mode is changed, and behavior with external and Bluetooth microphones. Until those are checked, a recording made with Voice Isolation on is not known to be noise-filtered.

## Mic Mode in Settings and a live microphone while choosing — October 28, 2026

Settings ▸ Recording now has a microphone menu and the same Mic Mode row as the record sheet, with an **Open Mic Settings** button (the camera's button is now **Open Camera Settings**). While the record sheet or the Recording pane is showing and the microphone is on and allowed, Hot Take keeps that microphone open without recording or saving anything, so macOS has an app using the microphone when its Mic Modes menu opens. The row shows the mode macOS is applying (`activeMicrophoneMode`) and says so when it differs from the one chosen. The monitor closes when the window closes and steps aside during any countdown, recording or save. Settings never triggers the microphone question; the record sheet may.

Open Mic Settings first makes sure the microphone is open and running, then asks macOS for the menu, because a probe on the test Mac showed the menu appears from a mic-only capture session but not with no session open (and not from a voice-processing `AVAudioEngine`). What it logs: subsystem `org.relaytake.mac`, category `microphone`, one line per click. An early report that the button did nothing with Presenter off came from a stale app: `swift build` does not update `build/Hot Take.app`, only `scripts/bundle.sh` does.

The Mic Modes menu showed the old clapperboard icon for Hot Take. The system's icon cache is keyed by bundle ID and version, and an old Relaytake.app had the same ones, so `bundle.sh` now sets `CFBundleVersion` to the commit count. On the test Mac the stale icon also needed the old app deleted, `/Library/Caches/com.apple.iconservices.store` cleared and a restart; after that the flame showed.

Not changed: recording still captures the microphone through ScreenCaptureKit for screen takes, and through a capture session only for camera-only takes. Switching screen takes to a capture-session microphone is not done, because it is not known that ScreenCaptureKit's microphone ignores Mic Modes.

Verified: the app builds in release, and on the test Mac a person saw Open Mic Settings open the Mic Modes menu with Presenter off, offering Standard and Voice Isolation. Not verified: that the row follows a change, what `activeMicrophoneMode` reports during a ScreenCaptureKit recording, behavior with external and Bluetooth microphones, and the tests (this Mac has no Xcode, so `swift test` cannot run here).

## Shortcuts, screenshots, camera takes, marks, joining and more — October 28, 2026

Added to the Mac app: global shortcuts and Quick Record, screenshots, camera-only takes, a speaker-notes window, leaving Notification Center out of captures, arrows, boxes and blurs and click rings in the Studio, joining takes, importing videos, playback speed, a chosen thumbnail, GIF export and a picture at each click.

Verified: the Swift tests pass (258), including real renders. A box, an arrow and a click ring were drawn into a saved video and found by measuring pixels where they belong and not elsewhere or afterward; marks stayed on their place when a zoom magnified the picture; a blur smoothed its own region of a striped picture and left the rest sharp, including inside a backdrop; two takes of the same size, and of different sizes, joined with the right length, picture and sound; MP4 and MOV imports produced an MP4 and a non-video was refused without leaving files; a GIF came out with the right frame count and size; a picture was saved at each click moment; a camera and a separately recorded sound were merged with the sound lined up by the delay given. The rules for shortcuts (which keys are refused, no two actions on one key, saved text read back), screenshot file names, and which apps are left out of a capture are unit tests. The Studio and Settings were drawn offscreen to PNGs (`--studio-snapshot … marks`, `--settings-snapshot`) and the release bundle built, signed and launched, with `--network-check` still blocking requests.

Not verified (no real capture, hardware or interaction was exercised): that the shortcuts fire from other apps and that another app holding the same keys is reported; that Quick Record starts a real recording; screenshots of a real screen, window or area; that Notification Center is the owner of the banner windows and so is really left out of a screen or area recording (needs a notification to arrive during a recording on a real Mac); a camera-only take from a real camera and microphone, including how well their start times line up (they start separately and are lined up by measured start times); that the speaker-notes window is absent from a real recording and screenshot; dragging marks' handles in the Studio with a pointer, and the Mark popover; the Join, Import, drag-and-drop, speed, Pictures menu, GIF and click-picture panels in the running app; and playback speed with real audio.

Added translation of the transcript (Transcript tab, Translate menu) with the system Translation framework, translations kept in the take's `.json`, saving a translation as `.vtt`, a caption language choice in the Studio, and line-length wrapping for text without spaces (Chinese, Japanese). The rules (putting translated text back into the lines with their timing, refusing a result that leaves a line out, dropping translations when the transcript changes, older notes and drafts still opening, wrapping unspaced text) live in RelaytakeCore with tests and pass with the rest of the suite. The Translation framework's own API was checked against the macOS 26.5 SDK interface and Apple's published documentation; the installed SDK is not a macOS 27 SDK, and the documentation seen showed no change for macOS 27, so nothing was checked against macOS 27. Not verified: any real translation (the tests never call the framework), the language-download prompt, the quality or speed of translations in any language, how the menu and the Studio picker look and behave on screen, and whether the system translator copes with the one-line-at-a-time requests on long recordings. It was built, not run.

## Suggested chapters — October 28, 2026

Added chapters as headings in the Transcript tab's transcript (with a Chapters menu to suggest, add, copy and remove them), a Chapters menu on the Watch page, chapters kept in the take's `.json`, and `--chapters`. Where a chapter starts is worked out by arithmetic on the transcript (`ChapterDetector`): at each line start it compares how much the words just before and just after share against how much each side holds together, smooths that over neighbouring lines so one chance dip does not count, and adds a little for a pause and for an opening phrase like "next". The on-device model is only asked to name each section; it is never asked for a time.

Verified (synthetic): the unit tests pass, covering clean and noisy made-up transcripts. A change of subject was found near where it was put, three subjects gave three chapters, a single subject with a wide vocabulary gave none in 20 seeded runs, a change was found in 20 seeded runs where one word in ten came from the other subject, a pause or an opening phrase alone never made a chapter, no chapter was shorter than the minimum, results did not depend on input order, and older notes without chapters still open. Saving chapters kept the rest of the take's notes.

Not verified: how well it divides real recordings. The thresholds were set against made-up transcripts, not real speech, so they are cautious guesses and will miss some real changes (a missed chapter is one click to add) and may add some that are not wanted. Not run: the on-device model naming a section (the tests never call it; a reply that is not a short title is refused and the section keeps its main words), the view on screen (clicking, renaming, adding at the playhead, the unsaved banner, the Watch menu), and recordings in languages other than English (the filler-word list is English; other languages still compare words but with less filtering, and Chinese and Japanese, which have no spaces between words, effectively fall back to pauses and opening phrases only, which are not enough alone, so they will usually get none). It was built, not run.

Chapters in Studio copies: a copy saved from the Studio carries the original's chapters, remapped through the cuts (`ChapterList.remapped`). Verified (synthetic): unit tests for no cut, a cut inside a chapter, a cut over a chapter's opening, a chapter cut entirely, a few moments left, the start of the recording cut, several cuts, and the copy's notes being kept when chapters are added. Not verified: a real Studio save carrying chapters into a real copy (the model's save path was built, not run), and chapters in joined takes (none are carried). Edits other than cuts do not move chapters; there is no speed change in the Studio today, so none is accounted for.

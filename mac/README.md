# Hot Take for Mac

A native Mac app for recording your screen to **MP4**, then captioning, summarizing and editing it, **entirely on your Mac**. MIT licensed. No account, no network service, no telemetry: the app refuses every web request it makes (see `--network-check` below).

## Requirements

- macOS 26 or later (it uses the system's on-device speech and language-model frameworks).
- The Swift 6.2 toolchain: the full developer tools, or just the command line tools (`xcode-select --install`).
- on-device intelligence turned on if you want the model-written titles, summaries and suggested edits. Without it you still get recording, captions and editing.

## Build and run

```sh
cd mac
./scripts/bundle.sh
open "build/Hot Take.app"
```

the system asks for **Screen Recording** (and Microphone if you record your voice) the first time; after allowing screen recording, quit and reopen the app. Captions use the system's speech models, which the system downloads the first time you use a language.

**Signing matters for permissions.** the system ties these grants to the app's code identity. The bundle script signs with an "Apple Development" certificate if one is in your keychain (or the one named in `RELAYTAKE_SIGN_IDENTITY`), so the grants survive rebuilds. A free developer certificate is enough. Without one it falls back to an ad-hoc signature, and the system forgets the Screen Recording grant after every rebuild. To reset the grants:

```sh
tccutil reset ScreenCapture org.relaytake.mac
tccutil reset Microphone org.relaytake.mac
```

(`org.relaytake.mac` is the app's bundle identifier, kept unchanged so existing installs keep their settings and permissions.)

Recordings are saved to `~/Movies/Hot Take/` as ordinary files (`Hot Take 2026-10-21 at 09.30.15.mp4` plus a `.vtt` captions file and a `.json` notes file with the same name). A Mac that already has recordings in `~/Movies/Relaytake/` keeps using that folder.

## Features

### Recording

- **Capture:** the system's screen-capture framework with its built-in MP4 writer (H.264), so files have correct duration and seeking. **New Take** opens a sheet. *Screen* shows each display as a live preview sized to the real screen (with its number when you have several). *Window or app* shows a preview of every open window, labeled with its app; pick one, or use *Use system picker…* to record a whole app. *Area* lets you drag a box. A browser is recorded as the window shows it, so switch to the tab you want first: the system does not let an app record one background tab. At the bottom, an optional **presenter** menu (the camera; off by default): choosing one asks for camera access, shows a live preview so you can check your framing, and has a **Video Effects…** button that opens the system's panel for background blur, Center Stage, Studio Light and similar effects, which apply to Hot Take's camera. While recording, a floating circle shows you and stands where you will appear in the video (bottom-left to start); drag it wherever you like, and it is never in the recording itself. The camera is recorded as a bubble where you left that circle; the plain screen recording and the camera file are kept in a hidden folder beside the take, so in the Studio's **Camera** button you can move (drag it in the preview or pick a corner), resize, reshape, mirror, border, hide or time-nudge the bubble, and Save Copy draws your choice. Camera files stay on your Mac and count toward the take's size. Also at the bottom, a **microphone** menu (any input your Mac has; Default follows the system), a **file size** menu (Small, Medium, Large or Custom, each with its size per minute), **Computer audio**, and a **No audio** box that records only the picture and hides the microphone menu. Restart reuses the same choice. While recording, the small control bar (timer, Restart, Stop) can be **dragged** anywhere on screen if it is in the way, by its grip or any empty part of it; it reappears where you left it next time (and back at the top if that screen is gone). With *Custom* file size, the estimate updates as you type and as you change the resolution or frame rate: *Auto* works out the video bitrate from those two (the same rule the Small, Medium and Large presets follow), or untick it to type your own. Hot Take keeps its own windows out of screen and area recordings by default; for **demoing the app itself**, tick *Show Hot Take in the recording* (screen and area), and its windows stay on screen and in the video (the floating control bar and countdown never appear in it). Choosing a Hot Take window in *Window or app* does the same. Windows opened after the recording starts are not included. Windows are listed only to draw these previews; nothing is recorded until you press Start.
- **Output:** `~/Movies/Hot Take/` as `Hot Take 2026-10-21 at 09.30.15.mp4` plus `.vtt` and `.json` with the same name. Share the files however you like.

### Library

- **Library:** the main window lists your recordings as a grid that adds columns as it widens (compact rows when narrow), with thumbnails, durations, summaries and tags, and search across all of them. **New Take** (⌘N) is in the toolbar; it becomes a red Stop button with a timer while recording. Play, rename, move and trash recordings, and open one to **Watch** it, read its **Transcript**, or edit it in the **Studio**.
- **Versions nest under their original:** when you save a copy from the Studio, the library files it under the recording it came from. The original shows a **“N versions”** pill on its thumbnail (a number in list view); click it to open the versions right after the original, tinted and marked *Version* with “Edited from …”, oldest to newest, and click again to fold them away. Searching shows every match, so nothing hides inside a folded group. Moving an original to a folder takes its versions along. The link is stored in the copy's `.json` (`derivedFrom`); copies made before that are recognized by “(edited)” in their name. Trashing an original leaves its versions as ordinary recordings.
- **Folders and navigation:** the sidebar button in the toolbar opens the folder list beside your recordings, and the window grows by its width to make room (closing it gives the width back). The window also has a minimum size for what it is showing, wide enough that the toolbar and its tabs are never folded away, and it grows to that size if you switch to a page that needs more room (for example opening the Info panel). Details: a folder list lists **All Recordings** and your folders. Create, rename, nest and trash folders from the sidebar; they are real folders under `~/Movies/Hot Take/` (a Mac that already has recordings in `~/Movies/Relaytake/` from before the rename keeps using that folder) that also work in a file manager. Drag a recording onto a folder, or use *Move to* in its right-click menu. Folders can have an **emoji icon**: right-click a folder and choose *Choose Icon…* (pick one, or type or paste any emoji; *No Icon* removes it). The emoji is simply the start of the folder's name (`🔥 Hot Takes`), so it also shows in the file manager, and renaming a folder keeps its icon. A **🔥 Hot Takes** folder is created the first time the app runs (once, so it stays gone if you trash it). New takes are saved into the folder you are viewing. Search filters by title, summary, tags and folder.
- **Selecting works like a file manager:** click selects, ⌘-click toggles, ⇧-click selects a range, and in the grid you can drag a box on empty space to select what it touches (hold ⌘ or ⇧ to add). ⌘A selects all, the arrow keys move (⇧ extends), Return or double-click opens, Escape clears, and Delete asks, then moves the selection to the Trash (never permanent). Drag the selected recordings onto a folder in the sidebar to move them all; dropping on All Recordings moves them back to the top level.
- **Right-click everywhere:** on a recording (Open, Rename, Move to, Show in Folder, Copy File Path, Move to Trash; with several checked it acts on all of them), on a folder or empty space in the sidebar (New Folder, Rename, Show in Folder, Refresh, Move to Trash), and on empty space in the library (New Take, New Folder, Select All, Show in Folder, Refresh). Scroll bars and bounce only appear when there is enough content to scroll.
- **Header actions:** when recordings are selected (or one is open), **Share**, **Edit** and **Trash** appear in the window header. Share opens the system share sheet with the video file(s), Edit opens the recording in the Studio (one recording at a time), and Trash asks first and moves to the Trash.
- **Playback modes:** hover over any video (the take's page and the Studio preview) for three buttons in its corner. **Theater** fills the whole window (Esc or *Exit Theater* to leave). **Pop out** opens the video in its own resizable window that floats above the others. **Full screen** goes straight to full screen (Esc to leave, and its window closes). Shortcuts: ⌥⌘T, ⌥⌘P, ⌥⌘F. In the Studio these show the edited preview with its text and a play and scrub bar. Pop-out and full-screen windows close when you leave that recording or the Studio.

### Watch, Transcript and Info

- **Transcript tab:** next to Watch and Studio. The video sits beside the full transcript; click a line to jump there (playback is left as it is), the line being spoken is highlighted, *Copy* copies it all and *Remake* listens again. **Edit > Find in Transcript** (⌘F, then ⌘G / ⇧⌘G) tints the matching lines and steps through them. Double-click a line (or right-click it and choose *Edit*) to change its words right there: Return or the check mark saves, Escape puts the old words back. Each line keeps its timing, and the captions file is rewritten to match. If a recording has no transcript yet, *Make Transcript* creates it on this Mac.
- **Info panel:** the **Info** button on a recording's Watch page (⌥⌘I) slides a panel in beside the video, which shrinks to make room, and it remembers whether you left it open. Edit a take's title, summary, tags and notes (saved automatically, kept in the `.json` beside the video) and see the file's size, duration, resolution, frame rate, codecs, audio layout, location and dates. The panel's **File** section also has **Show in Folder**, **Copy Path** and **Make Captions** (or *Remake Captions*), which writes the .vtt file and keeps your title, summary, tags and notes.
- **Write fields with the on-device model:** every editable field in the Info panel (title, summary, tags, notes) has a sparkle button, and *Generate All* fills them together. The transcript is made first if the take has none. Each generated field has an *Undo* until you edit again, and nothing leaves this Mac. Needs on-device intelligence.

### Studio

- **Studio tab:** one fixed screen, nothing scrolls, for editing a take. The preview plays the real edit (cuts, music, voiceover and text). Below it, five tracks fitted to the window: **Video** (frame thumbnails; **Splice** (the button by the time, or **S** or ⌘B) breaks the video at the playhead without removing anything; splice as many times as you like, click a part to choose it and press Delete (or *Remove*) to take it out, or *Keep Only This*. Drag a splice to slide it, drag the ends of a chosen part to trim in or out (pulling an edge back out brings back footage you removed), drag across the track to choose any stretch, or right-click for *Splice Here*, *Remove This Part* and *Remove Splice*. **[** and **]** drop everything before or after the playhead in the part it is in; scissors mark splices (dark) and removed gaps (orange)), **Text**, the recording's **Audio** (waveform, volume, mute), **Music** and **Voiceover**. *Add Text* puts words at the playhead (drag them on the preview, resize the bar to change how long they show; font, size, color, optional box). *Add Music* (or drop an audio file on the timeline) adds a background track that fits the video, loops if short, fades in and out, with its own volume. *Voiceover* counts down, plays the video muted, and records your microphone; optionally it replaces the original audio, so you can redub a whole recording. Everything sits on the edited timeline, so a cut ripples through text and voiceover and a voiceover that straddles a cut is split to stay in sync. *Tighten* finds long pauses and restarts to cut (below). Undo and redo cover all of it, and **Save Copy** renders a new MP4 (text is drawn into the frames) beside the original, which is never changed. **Save Copy** has a *Save Options* button beside it: keep the original quality or pick **Small, Medium, Large or Custom** (with a size estimate), include or leave out the audio, and **export to a file** as MP4, MOV or WebM wherever you choose. A copy that is only smaller (no edits) keeps the original's captions and notes; a copy with edits gets fresh captions and a summary. The Studio replaced the old Edit tab, so there is one editor. The *Voiceover* options and the bar under the timeline have a **microphone picker** (any input your Mac has; "Default" follows the system, and an unplugged choice falls back to it).
- **Background and Auto Zoom (Studio):** two tools for polishing a recording, both applied in the Studio and drawn into the picture when you save a copy (your original is never changed). **Background** puts the recording on a gradient or solid color with the window inset, rounded and shadowed, with sliders for margin and rounded corners. It pairs with *Window or app* recording, which captures just that window with no menu bar or desktop around it (a window's own drop shadow is left out so the backdrop can supply one). **Auto Zoom** uses the mouse clicks noted while recording (only where and when you clicked, never which app or what you typed, and nothing leaves your Mac): *Zoom In on My Clicks* adds a zoom around each group of clicks, easing in and back out. Each zoom is a block on the **Zoom** track: drag it to move, drag its ends to resize, click it to change how far it zooms, and click the video to point it at a different spot. Cutting a section moves or removes the zooms with it. Recordings made before this feature have no clicks, but you can still add a zoom by hand.
- **Captions in the Studio:** the **Captions** button turns on captions drawn into the picture, so they show in any player (they are saved into the copy and cannot be turned off afterward; your original is never changed). They use the transcript, made first if needed. Choose a style (**Classic** white on a dark box, **Bold** large with a shadow, **Minimal** small and quiet, **Highlight** dark on yellow) and a position (top, middle or bottom). Cuts carry the captions with them: a removed section removes its captions. These are always-visible (burned-in) captions; a selectable subtitle track is not offered.
- **Tighten:** the *Tighten* tool finds two things and draws them on the Video track as dashed orange stretches. **Long pauses** (you choose 1, 2 or 3 seconds) are measured from the audio levels and the transcript's timing, not by the model: a language model reads text and cannot hear. A little breathing room stays at each end of a pause you cut. **Restarts** are a sentence said again straight afterwards, or started and then said whole; they are found by comparing the words of neighboring transcript lines, so the same transcript always gives the same answer, and the on-device model, if it is there, is asked only for restarts the comparison missed (it is told to answer *none* for a clean recording). Hover a stretch to cut it (one undoable step) or keep it; *Cut All Pauses* cuts every pause at once, and restarts are always cut one at a time. Finding things changes nothing, and nothing is cut automatically.

### About

**About Hot Take** (app menu or the menu bar icon) shows the version and build, what the app promises about privacy, links to the source, issue tracker, license and third-party notices on GitHub, and a button that copies the app version, system version and Mac model for bug reports (copied only when you press it). The GitHub address is set in one place, `AppInfo.repository` in `Sources/Relaytake/AboutView.swift`.

### On-device speech and writing

- **Captions and speech recognition:** the system's on-device recognizer writes a `.vtt` file beside the video, through the shared **PlainspokenSpeech** package (the speech layer Plainspoken uses). In Settings → Captions & Summary you can pick the **language** (including regional models such as English (India); the first use of a language downloads the system's model through the system), the **recognizer** (the newer SpeechTranscriber or the classic DictationTranscriber), and a **vocabulary** file of names and terms. A plain term fixes casing and near-misses; an alias such as `pull request=pool request` or `Rovo=bravo|robo` fixes words the recognizer keeps mishearing. Recordings with several audio tracks (microphone and system sound) are mixed so every voice is captioned. The app refuses every web request it makes, so nothing here leaves your Mac. Whisper is not included.
- **Title and summary:** the system's on-device language models write a title and a short summary into a `.json` file that also holds the timed transcript. Needs on-device intelligence to be enabled; if it isn't, you still get the video and captions.

## File size and compression

Choose Small, Medium, Large, or Custom in New Take or Settings. Medium is the default. Custom appears after Large and exposes resolution (360p–2160p), frame rate (5–60 fps), video bitrate (200–20,000 kbps), AAC audio bitrate (32–256 kbps), and mono/stereo audio. The estimated size updates with these values. Custom preferences are remembered and also apply to editor exports; each recording or export snapshots its settings when it starts.

| Preset | Maximum resolution | Frame rate cap | Target video | AAC audio | Approx. MB/min |
| --- | --- | --- | --- | --- | --- |
| Small | 1280 × 720 | 15 fps | 700 kbps | 64 kbps mono | 6 |
| Medium | 1920 × 1080 | 24 fps | 1.6 Mbps | 96 kbps stereo | 13 |
| Large | 2560 × 1440 | 30 fps | 3.5 Mbps | 128 kbps stereo | 28 |

Small suits compact walkthroughs; Medium favors readable UI text; Large keeps more detail and motion. Size estimates use target bitrates, decimal MB, and include one mixed audio track; actual sizes vary with content. Output never upscales the source. Portrait and ultrawide recordings keep their aspect ratio within the preset bounds. The capture framework applies the resolution/frame-rate cap during capture. After recording, a local H.264/AAC optimization pass replaces the initial file only if the completed output is smaller; a failed pass leaves the initial recording available. Closing the app before this pass finishes can leave a larger raw recording; temporary work is isolated in `.relaytake-processing`.

For existing takes, open the **Studio**, choose **Save Options**, turn off *Keep original quality* and pick a preset (optionally turning off audio), then **Save Copy**. With edits it is the same Save Copy. Both preserve the original video. Compression-only copies preserve captions and metadata; edited copies regenerate them according to Settings. Compression can make an already-small file larger; compare the original size with the estimate first. Saving requires temporary free space for a second file.

Synthetic validation (requires ffmpeg/ffprobe): `python3 mac/scripts/check-compression.py`. This checks actual output resolution, frame rate, duration, AAC channels, full decoding, silent export, and refusal to overwrite a source file. Live capture quality and UI interactions still need manual verification.

### Export formats

In the Studio, **Save Options → Export to a file** saves the current edit to a chosen location as MP4 (H.264/AAC, the default recording format), MOV (H.264/AAC in a MOV container), or WebM (VP9/Opus). Quality and audio controls apply to exports. The source recording stays unchanged; Save copy continues to create MP4 copies in the library. MOV is a compatibility choice, not an extra compression level. WebM uses a quality target plus the selected bitrate ceiling, so actual size can vary and encoding can take longer.

MP4 and MOV use system encoders. WebM requires FFmpeg with `libvpx-vp9` and `libopus`, discovered in the app’s executable directory or standard install locations (such as `/opt/homebrew/bin` and `/usr/local/bin`). It is disabled when no encoder is found. FFmpeg is not bundled by this repository; distributors adding it must include its applicable license notices and dependencies. WebM currently uses a temporary MP4 intermediate, adding an encoding pass and temporary disk usage. Exports are completed in a temporary directory beside the destination before replacing an approved existing file. Recording and library playback remain MP4-based.

Run `python3 mac/scripts/check-formats.py` after building to validate actual MP4/MOV/WebM containers, codecs, audio removal, full decoding, duration, source preservation, and temporary-file cleanup. These synthetic checks do not validate the native save-panel UI.

### Screen-recording compression

MP4/H.264 + AAC remains the default. The post-recording encoder uses an average bitrate target, H.264 High profile, explicit CABAC entropy coding and frame reordering, with at most two seconds between keyframes. Unchanged regions can reuse earlier frames; there is no bespoke static-scene detector or claim to match any commercial encoder. These offline options do not add latency to capture. MP4 metadata is placed ahead of media for progressive playback. A size estimate is not a fixed-size guarantee, and low-resolution presets can still reduce text legibility.

`python3 mac/scripts/check-static-screen.py` compares a synthetic 1080p text screen with motion at the same preset, checks decoded image similarity and fast-start layout. It is a regression check, not evidence of real-world text readability at every preset. Hosted HLS/DASH adaptive playback would require multiple renditions and a player/hosting pipeline; it is not part of local exports.


## Command-line checks

The app doubles as a small toolbox for scripted checks (run the executable inside the bundle):

```sh
APP="build/Hot Take.app/Contents/MacOS/Hot Take"
"$APP" --network-check                         # proves web requests are refused; exits 0 when blocked
"$APP" --process video.mp4                     # captions, title and summary for an existing video
"$APP" --cut in.mp4 out.mp4 START END          # remove START–END seconds (same code as the Studio)
"$APP" --suggest "/path/to/Take.mp4"           # long pauses and restarts (changes nothing)
"$APP" --fields "/path/to/Take.mp4"            # the title, summary, tags and notes the model writes
"$APP" --splice-check "/path/to/Take.mp4"      # drives the Studio's splice and trim model on a real file
"$APP" --studio-snapshot Take.mp4 song.m4a out.png   # draws the Studio to a PNG
"$APP" --about-snapshot out.png                # draws the About window to a PNG
```

## Tests

```sh
./scripts/test.sh                      # the core library tests
(cd Packages/PlainspokenSpeech && ./scripts/test.sh)   # the speech package (runs the real recognizer)
```

`scripts/test.sh` adds the flags SwiftPM needs when only the command line tools are installed; with the full developer tools it is just `swift test`. The core tests cover caption formatting, file naming, metadata, summary parsing, the cut and splice model, folders and versions, the Studio's text, captions, zoom and background rendering (through real exports), and capture geometry. They do not cover live capture, the permission prompts, or the interface views.

## Status and limits

Hot Take for Mac is a **pre-release (0.1)**. It builds and its tests pass, and most features have been exercised on one Mac (macOS 27 beta, ARM processor), but it has not been tested across Macs or system versions. [docs/compatibility.md](../docs/compatibility.md) records exactly what was verified and how, feature by feature, and what was not.

- **Not verified:** long recordings; microphone plus system-audio mixing in every combination; window recordings that move while recording; area recordings; playback of produced files in every other app; multiple displays beyond the one tested; accessibility.
- **Capture limits:** a browser *tab* cannot be captured on its own (the system only sees windows), so record the browser window or drag an area over the page. An area is a fixed part of the screen and does not follow a window that moves. If the recorded window closes or the display disconnects, the take is stopped and saved. Pause is not supported (the system recorder has none).
- **Auto Zoom** follows recorded clicks only; the zoom's focus stays fixed rather than tracking the pointer.
- `@Generable` is not used, so the build does not need the full developer tools; the model is asked for a fixed `TITLE:`/`SUMMARY:` format instead.
- Not implemented: cloud upload or sharing links, a global hotkey, and Intel Macs have not been considered.

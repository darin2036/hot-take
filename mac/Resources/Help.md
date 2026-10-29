# Hot Take Help

<!--
This file is the text of Help ▸ Hot Take Help. Each "## " heading is one topic in the Help window's sidebar.
Write for someone using the app, not for a developer: what to click and what happens. Supported markup:
"### " subheadings, "- " bullets, blank-line separated paragraphs, **bold**, *italic*, `code`, [links](https://…).
Every change to what the app does must be reflected here (see AGENTS.md).
-->

## Getting started

Hot Take records your screen to an ordinary MP4 video, then writes captions and a summary and lets you edit it, all on your Mac. There is no account to make and nothing is uploaded.

### The welcome screen

The welcome lasts about three seconds. At launch, the flame icon appears in a violet glow with flowing light trails, followed by “What’s your Hot Take?” Click anywhere or press any key to skip into the library. To turn it off, open **Settings ▸ Library** and turn off **Show the welcome animation**. With macOS **Reduce Motion** enabled, the artwork and words stay still and fade away into the library.

### Make your first recording

- Click **New Take** (⌘N) in the library's toolbar, or choose it from the menu bar icon.
- Pick what to record: a **Screen**, a **Window or app**, an **Area**, or just your **Camera**.
- Choose a microphone and a file size, then press **Start recording**. A short countdown runs first.
- Press **Stop** when you are done. Hot Take saves the video, then makes captions, a title and a summary in the background.

### Where things are saved

Recordings are saved in `~/Movies/Hot Take/` as normal files: `Hot Take 2026-10-21 at 09.30.15.mp4`, plus a `.vtt` captions file and a `.json` file that holds the title, summary, transcript and your notes. You can move or share them like any other file.

### The first time you record

macOS asks for **Screen Recording** permission (and Microphone or Camera if you use them). After you allow Screen Recording, quit and reopen Hot Take. See *Permissions and privacy* if a prompt does not appear.

## Recording

### Choosing what to record

- **Screen** shows a live preview of each display. Pick one.
- **Window or app** shows a preview of every open window. Pick a window, or use *Use system picker…* to record a whole app. A browser is recorded as the window shows it, so switch to the tab you want first.
- **Area** lets you drag a box on the screen.
- **Camera** records your camera and microphone with no screen. See *Camera and presenter*.

### Options in the record sheet

- **Microphone:** any input your Mac has. *Default* follows the system. Under it, the **Mic Mode** row shows what macOS is applying (Voice Isolation helps in a noisy room) and **Open Mic Settings** opens the system's menu to change it.
- **File size:** Small, Medium, Large or Custom, each with its size per minute. See *File size and quality*.
- **Computer audio:** records the sound your Mac plays.
- **No audio:** records only the picture and hides the microphone menu.
- **Show Hot Take in the recording:** Hot Take's own windows are normally kept out of screen and area recordings. Tick this when you are demoing Hot Take itself.
- **For an agent:** see *Record for a coding agent*.

### Recording sounds

The 3–2–1 countdown plays a short tone with each number, with a higher tone on 1. A descending chime plays when capture ends; saving and captions may still be in progress. Canceling the countdown silences it. Pause, Resume and Rewind do not play the end chime. Restart plays a fresh countdown.

Sounds are on by default. Turn off **Play recording sounds** in Settings ▸ Recording for a quiet countdown and stop. They use your Mac’s current audio output and volume, including when **No audio** is selected (that option controls the take’s audio). Countdown tones play before capture begins, and the end chime is triggered after capture stops.

### While recording

- The small control bar shows the timer with **Pause**, **Rewind**, **Restart** and **Stop**. Drag it anywhere it is out of your way; it remembers where you left it.
- **Pause** leaves the paused time out of the take. Press **Resume** to carry on.
- **Rewind** goes back 10 seconds and pauses there, throwing away what you recorded since (the picture, the sound, your camera and the clicks noted for zooms). Say it again, then press **Resume**. Press Rewind again to go back another 10 seconds, even from a pause. It works wherever Pause does, so not on a camera-only take. It keeps at least the first second of the take, and says so if there is not enough yet to rewind. It is also in the Record menu and has a shortcut (below). What you rewound over is gone; there is no undo.
- **Restart** throws away the take and starts again with the same choices.
- If the recorded window closes or a display disconnects, the take is stopped and saved.

### Hiding notifications

Settings ▸ Recording ▸ **Hide notifications in recordings** (on by default) leaves Notification Center out of screen and area recordings and screenshots, so a banner that pops up is not in your video. It does not turn on Do Not Disturb.

## The menu bar

Everything in Hot Take is also in the menu bar, in the usual places:

- **File:** New Take (⌘N, or Stop Recording while recording), New Folder… (⇧⌘N), Open Hot Take File… (⌘O), Open Recent, Import Video… (⇧⌘I), Save Project… (⌘S, in the Studio), Save Copy (⇧⌘S, in the Studio), Export (below), Show in Finder (⇧⌘R) and Show Library Folder.
- **Edit:** the system's items, plus Find in Transcript (⌘F, ⌘G, ⇧⌘G).
- **View:** Back to Library (⌘[), Show or Hide Info Panel (⌥⌘I) and Refresh Library (⌘R).
- **Record:** New Take, Pause or Resume, Rewind 10 Seconds, Restart Take, Quick Record, Quick Take for Agent, Take Screenshot and Speaker Notes (⌥⌘N).
- **Take:** for the open or selected recordings: Open, Rename…, Join Recordings, Copy for Agent, Copy Bug Report, Copy File Path and Move to Trash….
- **Studio:** while a Studio is open: Play / Pause, Splice at Playhead (⌘B), Add Text, Add Music…, Add Zoom at Playhead and Remove Selection.
- **Help:** Hot Take Help (⌘?) and What's New.

Items that do not apply right now are greyed out.

## Shortcuts and Quick Record

Settings ▸ Recording ▸ *Shortcuts and notes* has shortcuts that work from any app.

- **Start or stop recording:** ⌃⌥⌘R
- **Pause or resume:** ⌃⌥⌘P
- **Rewind 10 seconds while recording:** ⌃⌥⌘W
- **Take a screenshot:** ⌃⌥⌘S
- **Start or stop a take for an agent:** ⌃⌥⌘A

### Changing a shortcut

Click the shortcut, press the keys you want, and use **Reset** or **Off** if you change your mind. A shortcut needs ⌘, ⌥ or ⌃. Hot Take refuses system shortcuts (such as ⌘Space or ⇧⌘4), two actions on the same keys, and keys another app already holds, and tells you why. These shortcuts need no extra permission, and Hot Take sees only those exact keys.

### Quick Record

**Quick Record** (the start/stop shortcut, or the menu bar item) records the screen you recorded last, or your main screen, with your last settings, after the usual countdown and with no sheet.

### Other useful shortcuts

- **New Take:** ⌘N
- **Speaker Notes:** ⌥⌘N
- **Import Video:** ⇧⌘I
- **Info panel:** ⌥⌘I
- **Theater, Pop out, Full screen** on a video: ⌥⌘T, ⌥⌘P, ⌥⌘F
- **Find in Transcript:** ⌘F, then ⌘G and ⇧⌘G
- **Save Project** (in the Studio): ⌘S
- **Splice** (in the Studio): S or ⌘B

## Screenshots

- Use the record sheet's **Screenshot** button (it captures whatever is chosen: screen, window or area), the menu bar item, or the screenshot shortcut.
- A PNG named like `Hot Take Screenshot 2026-10-21 at 09.30.15.png` is saved into the folder you are viewing. Hot Take's own windows are never in it.
- Screenshots are files in the folder, not library entries. Open the folder (the banner has a **Show** button) to see them.

## Camera and presenter

### Putting yourself on the screen

In the record sheet, choose a **presenter** (your camera) to show yourself as a bubble over the recording. Choosing one asks for camera access and shows a live preview so you can check your framing. **Video Effects…** opens the system's panel for background blur, Center Stage and similar effects.

While recording, a floating circle shows where you will appear (bottom-left to start). Drag it where you like. The circle itself is never in the recording.

### Changing the bubble afterward

Hot Take keeps the plain screen recording and the camera footage separate, so in the Studio's **Camera** button you can move the bubble (drag it, or pick a corner), resize it, reshape it, mirror it, add a border, hide it, or nudge its timing. **Save Copy** draws your choice. Camera files stay on your Mac and count toward the take's size.

### Camera-only takes

Choose **Camera** as the source to record your camera and microphone with no screen. Computer audio is not part of it, and it cannot be paused (Restart works). It gets captions and a summary like any take.

## Speaker notes

Open **Speaker Notes** from Settings, the menu bar or ⌥⌘N. It is a floating window for what you want to say, with a text size control and a reading-time estimate. Your notes are kept between sessions. The window is never in a recording or screenshot, and it asks the system not to share it.

## Record for a coding agent

Turn a walkthrough into a request for a coding agent such as Claude Code, Codex or Cursor.

### How to do it

- Tick **For an agent** beside Start recording, or use **Quick Take for Agent** in the menu bar (⌃⌥⌘A), or choose **For Agent** on any take's Watch page.
- Talk through what you want while you show it. Click on the things you mean.

### What you get

When you stop, Hot Take takes a picture at each click (a red ring marks the spot) and at each stretch of talk with no click, at most 20. It lays out what you said beside the nearest picture, followed by the full transcript. With on-device intelligence it also writes a goal and steps from your narration, marked as the model's reading.

The result is `PROMPT.md` plus a `frames` folder in a hidden `.hot-take-agent` folder beside the take. It moves and is trashed with the take. The text is copied with the pictures' full paths so an agent on this Mac can open them. Paste it into your agent yourself.

### Privacy

Nothing is uploaded. Only the time and position of clicks are used: not which app or link, and not what you typed.

## Make a bug report

Turn a walkthrough of a bug into a ticket you can paste into Jira, Slack, GitHub or a service desk: a title, a short description, steps to reproduce with a picture on each step, and what you expected and what happened.

### How to do it

- Record the bug. Show it happening, click the things you mean, and say what you do, what you expected and what went wrong.
- Open the take and choose **Bug Report** above the video. If the take has no transcript yet, Hot Take makes one first.
- Read the draft and fix anything. Edit the title, summary, expected and actual, change a step's words, remove a step you do not want, or add one. A step left empty is not used. Fill in **Environment** (browser, app version) if it helps. Your edits are kept, and choosing **Bug Report** again reopens them. **Start Over** drafts it again from the recording.
- Choose a **Format** for where it is going, then **Copy Title** and **Copy Text**: *Markdown* for GitHub, Linear, Jira Cloud and most service desks, *Jira* for Jira Server and Data Center, *Slack* (the title leads the message), or *Plain text*.
- Attach the pictures by dragging them from the draft into your ticket or message, or choose **Show Pictures**. **Show Recording** finds the video to attach.

### What it writes for you

With on-device intelligence, Hot Take drafts the title, summary, expected and actual, and words each step from what you said around each click. It uses only what you said and leaves out what you did not say. Without it, each step starts as what you said at that picture. Either way, check it before you send.

Each picture is taken at a click (a red ring marks the spot) or at a stretch of talk with no click, at most 20, and each step names its picture file.

The draft, `BUG-REPORT.md` and the pictures are in a hidden `.hot-take-bug-report` folder beside the take. It moves and is trashed with the take.

### Privacy

Nothing is uploaded, and Hot Take does not attach anything to your ticket. Only the time and position of clicks are used: not which app or link, and not what you typed.

## The library

The main window lists your recordings as a grid (compact rows when narrow) with thumbnails, durations, summaries and tags.

### Finding and organizing

- **Search** looks across titles, summaries, tags and folder names.
- The **sidebar** button opens your folders. They are real folders under `~/Movies/Hot Take/`, so they also work in Finder. Create, rename, nest and trash them from the sidebar.
- Right-click a folder and choose **Choose Icon…** to give it an emoji.
- Drag recordings onto a folder, or use **Move to** in the right-click menu. New takes are saved into the folder you are viewing.

### Selecting

Click selects, ⌘-click toggles, ⇧-click selects a range, and you can drag a box on empty space in the grid. ⌘A selects all, arrow keys move, Return or double-click opens, Escape clears. **Delete** asks first, then moves to the Trash. Nothing is ever permanently deleted.

### Versions

When you save a copy from the Studio it is filed under the recording it came from. The original shows an **“N versions”** pill. Click it to fold the versions open or closed.

### Join and import

- Select two or more recordings and choose **Join** to make a new take from them, in the order they were recorded.
- **File ▸ Import Video…** (⇧⌘I), or dropping MP4, MOV or M4V files on the library, copies them in as new takes and gives them captions and a summary. Your originals are not changed.

### Header actions

With recordings selected (or one open), **Share**, **Edit** and **Trash** appear in the window header. Share opens the system share sheet, and Edit opens the recording in the Studio.

## Watch, Transcript and Info

### Watch

In a narrow window the buttons above the video shrink to icons (hover for the name) and then move below the title. Play the recording. Hover over the video for **Theater** (fills the window), **Pop out** (a floating window) and **Full screen**. The speed menu plays at 0.5× to 2×. **Pictures** can use the current frame as the thumbnail, save a GIF, or save a picture at each click. **Bug Report** and **For Agent** turn the take into a bug report ticket or a request for a coding agent (see *Make a bug report* and *Record for a coding agent*).

Under the video, **Summarize with AI** reads the whole transcript and writes the summary with the on-device model (the transcript is made first if there is none). It replaces the summary that was there, and **Undo** puts the old one back. Nothing leaves your Mac. It needs on-device intelligence; without it the button is dimmed and its tooltip says why.

### Transcript

- The video sits beside the full transcript. Click a line to jump there. The spoken line is highlighted.
- Drag the thin bar between the video and the transcript to make the video bigger and the transcript narrower, or the other way round. Double-click the bar to put it back. Hot Take remembers the width.
- **Summarize** (the sparkle button) reads the whole transcript with the on-device model and writes a short summary, shown in a card above the lines. It is meant for long recordings: a very long one is read in parts, so it takes longer. The summary is the same one shown on the Watch page and in Info; it replaces the old one, and **Undo** puts that back. **Hide** collapses the card, and **Copy** copies the summary. It needs on-device intelligence; without it the button is dimmed and its tooltip says why. Nothing leaves your Mac.
- **Copy** copies it all, and **Regenerate** has the on-device AI listen again (it asks first, since it replaces your corrections). If there is no transcript yet, **Make Transcript** creates one on this Mac.
- **Edit ▸ Find in Transcript** (⌘F) tints matching lines. Press ⌘G and ⇧⌘G to step through them.
- Double-click a line (or right-click ▸ **Edit**) to fix its words. Return saves and Escape cancels. The captions file is rewritten to match.

### Translating a transcript

The **Translate** menu translates the transcript into another language on this Mac. The first use of a language may ask macOS to download it. Switch between the spoken words and each translation, **Save … Captions…** as a `.vtt` in that language, or remove one. Translations are read-only and are dropped if you correct or remake the transcript.

### Info panel

The **Info** button (⌥⌘I) opens a panel beside the video, and you can drag the bar between them to make the panel wider or narrower (double-click the bar to reset). Edit the title, summary, tags and notes (saved automatically) and see the file's size, duration, resolution and more. The sparkle button on each field writes it with the on-device model, and **Generate All** fills them together. Each result has an **Undo**. The **File** section is collapsed until you open it, and shows the file's details and **Show in Folder**. Make or remake captions from the Transcript.

## Chapters

Chapters split a recording into parts and appear as headings in the Transcript. Manage them from the transcript's **Chapters** menu.

- They are found automatically when a transcript is opened. Turn that default off in Settings ▸ Processing ▸ **Find chapters in transcripts**, or use the **Chapters** switch for one recording (off hides them and keeps any saved).
- **Find Chapters** looks for changes of subject, and the on-device model names each part. Recordings under 90 seconds, or with no clear change of subject, get none, so add your own.
- Rename a chapter, move it to the current time, or delete it. Start one with **Add Chapter Here** or by right-clicking a line.
- **Copy Timestamps** writes `0:00 Title` lines for a video description. The Watch page's **Chapters** menu jumps between them, and the Studio's ruler marks them.
- A copy saved from the Studio keeps your chapters at the times their footage now plays.
- MP4 and MOV files saved or exported from the Studio (Save Copy, Export, and Share) carry the chapters inside the file, so QuickTime Player and most video players show a list of them and jump to each one. WebM files do not carry chapters. Chapters that are off for a recording are left out.

## The Studio

The Studio is where you edit a take. It is one fixed screen: a preview that plays the real edit, with tracks below it for **Video**, **Text**, **Audio**, **Music** and **Voiceover**.

### Cutting

- **Splice** (S or ⌘B) breaks the video at the playhead without removing anything. Click a part and press **Delete** (or *Remove*) to take it out, or *Keep Only This*.
- Drag a splice to slide it. Drag the ends of a chosen part to trim; pulling an edge back out brings the footage back.
- **[** and **]** drop everything before or after the playhead in the part it is in.
- With the Audio track selected, splicing cuts the sound on its own.
- Everything sits on the edited timeline, so a cut ripples through text, marks, zooms and voiceover.
- **Undo** and **Redo** cover all of it.

### Edit by transcript

The **Transcript** button (the lines icon at the top of the Studio) shows the take's transcript beside the preview. Cutting a line cuts the video it was spoken over.

- Click a line to jump to it. **Shift-click** selects a run of lines and **Command-click** adds or removes one.
- Press **Delete** or click **Cut Lines** to cut the selected lines. Right-click a line for *Cut* and *Bring Back*.
- Cut lines are struck through and stay in the list. Select them and click **Bring Back** to put that footage back where it was. A line with only some of it cut says *Partly cut*.
- A cut here is the same as a cut on the timeline: it ripples through text, marks, zooms and voiceover, and **Undo** reverses it.
- With no transcript yet, **Make Transcript** creates one on this Mac.

Cuts follow each line's timing, so a cut can take a moment of the pause before or after the words.

### Text, music and voiceover

- **Add Text** puts words at the playhead. Drag them on the preview, resize the bar to change how long they show, and choose font, size, color and an optional box.
- **Add Music** (or drop an audio file on the timeline) adds a background track that fits the video, loops if short, fades in and out and has its own volume.
- **Voiceover** counts down, plays the video muted, and records your microphone. You can have it replace the original audio.

### Tighten

**Tighten** removes the long pauses (2 seconds or more) and the filler words ("um", "uh", "er", "ah" and "hmm") in one step. It says how many it removed, and you can undo it. A little breathing room stays at each end of a pause so no word is clipped.

Filler words are found from the time the speech recognizer gives each word, on this Mac. The first time, it listens to the recording once more with Apple's SpeechTranscriber, even if Settings uses the classic dictation model, because that model leaves out "um" and "uh". This doesn't change your transcript. Filler words work in English only; pauses work in any language. Words like "like" and "you know" are left alone, since they are often real words.

### Looks: Background, Auto Zoom, Captions, Marks

- **Background** puts the recording on a gradient or solid color with the window inset, rounded and shadowed.
- **Auto Zoom** adds a zoom around each group of clicks. Each zoom is a block on the Zoom track: drag it to move, drag its ends to resize, and click the video to point it somewhere else. Recordings made before click tracking have no clicks, but you can add a zoom by hand.
- **Captions** draws captions into the picture so they show in any player. Choose a style (Classic, Bold, Minimal or Highlight) and a position. A **Language** picker uses a translation if you made one.
- **Mark** adds an **arrow**, **box** or **blur** (to hide a name, email address or key). Drag its handles on the picture to place it. The same popover turns on **rings at each click**.
- **Find Sensitive Info…** in the Mark popover looks for email addresses, phone numbers, street addresses, card and ID numbers, keys, tokens and passwords on screen, plus any words you list (your name, a client, a hostname). It never runs on its own: it starts only when you click **Look Through Recording**, shows a progress bar while it reads the recording, and **Stop** cancels it. It then lists what it found, with most of each item hidden. Untick anything to leave alone, click a time to see it, and **Add Blurs** turns the rest into ordinary blurs on the Marks track, in one step you can undo. Text that scrolls is covered along the way it moved, and each blur starts a moment early and ends a moment late. Anything only in parts you cut out is skipped. The text is read on this Mac with the system's text recognition, and nothing is uploaded. It can miss small, blurry or briefly shown text, so always watch the video through before you share it.

## Saving and exporting

### Save Copy

**File ▸ Save Copy** (⇧⌘S, while the Studio is open) renders a new MP4 beside the original, which is never changed. Text, marks, captions, backdrop and zooms are drawn into the video. **Save Options** in the Studio's top bar lets you keep the original quality or choose Small, Medium, Large or Custom, include or leave out the audio, and **export to a file** as MP4, MOV or WebM wherever you choose.

WebM needs FFmpeg installed on your Mac; the option is greyed out when it is not found.

### Save Project

**Save Project** (⌘S) writes a `.hottake` file with the recording and your edit. Open it later from **File ▸ Open Hot Take File…**, or hand it to someone else. Choosing **Done** with an unsaved edit asks whether to Save Project or Discard Edits. Hot Take also keeps a hidden recovery copy of an unfinished edit so a crash does not lose your work.

### File ▸ Export

**File ▸ Export** has two kinds of export, both saved wherever you choose without adding anything to your library:

- **MP4, MOV or WebM Video…** exports video with your **Save Options** (original quality and sound unless you changed them). Select one recording in the library, or open it in Watch or Transcript, to export that file. While its Studio is open, export uses the current edit. Select only one recording to enable export.
- **Transcript as Markdown…** saves a `.md` file with the title, summary, tags, and each transcript line with its time, under your chapter headings. It uses the open recording, or the single recording selected in the library, and needs a transcript to exist already.

### Share

**Share** in the Studio sends the current edited version, not the original file.

## File size and quality

Choose a size in the record sheet or Settings. **Medium** is the default.

- **Small:** 720p at 15 fps, about 6 MB a minute. Good for quick walkthroughs.
- **Medium:** 1080p at 24 fps, about 13 MB a minute. Keeps UI text readable.
- **Large:** 1440p at 30 fps, about 28 MB a minute. More detail and motion.
- **Custom:** set the resolution, frame rate, video and audio bitrate, and mono or stereo. The estimate updates as you type.

After recording, Hot Take re-encodes the file only if the result is smaller. Quitting before that finishes can leave a larger recording, which is still fine to use. To shrink an existing take, open it in the Studio, choose **Save Options**, turn off *Keep original quality* and pick a size, then **Save Copy**. You need free disk space for the second file.

## Captions and summaries

- Captions and transcripts are made on your Mac by macOS's speech recognizer.
- Long recordings are read all the way through. The on-device model takes a few thousand words at a time, so Hot Take has it summarize each part and then writes the title, summary, tags, notes, agent request and suggested cuts from all of them. A very long take just takes longer.
- In Settings ▸ Captions & Summary, choose the **language**, the **recognizer**, and a **vocabulary** file of names and terms. A plain term fixes spelling and casing; an alias such as `pull request=pool request` fixes a word the recognizer keeps mishearing.
- Titles and summaries are written by the on-device language model. If on-device intelligence is off, you still get the video and captions.
- You can turn captions, summaries and chapters off for new recordings in Settings.

## Permissions and privacy

### What Hot Take asks for

- **Screen Recording:** to record screens, windows and areas.
- **Microphone:** to record your voice.
- **Camera:** for the presenter bubble and camera-only takes.
- **Speech Recognition:** to make captions on this Mac.

Settings ▸ **Permissions** shows each one and opens the right System Settings pane.

### Privacy

Everything happens on your Mac. Hot Take has no account, no telemetry and no web service, and it refuses every web request it makes. Windows are listed only to draw the previews, and nothing is recorded until you press Start. Clicks are noted by time and position only.

### Resetting permissions

If a permission seems stuck, quit Hot Take and run these in Terminal, then reopen it so macOS asks again.

- `tccutil reset ScreenCapture org.relaytake.mac`
- `tccutil reset Microphone org.relaytake.mac`

## Troubleshooting

- **Screen Recording keeps asking:** a build signed ad hoc loses the permission each time it is rebuilt. Quit and reopen after allowing it. Builds signed with a developer certificate keep it.
- **No titles, summaries or chapter names:** turn on Apple Intelligence (on-device intelligence) in System Settings. Without it you still get captions, and chapter titles are each part's main words.
- **A captions language will not work:** the first use of a language downloads a model through macOS, which needs your OK and a connection once.
- **No microphone Mic Mode menu:** macOS shows Mic Modes only for an app with the microphone open. Hot Take holds it open (without recording) while the record sheet or Recording settings is showing.
- **A browser tab cannot be recorded alone:** macOS only sees windows. Record the browser window, or drag an Area over the page.
- **WebM is greyed out:** install FFmpeg (with `libvpx-vp9` and `libopus`).
- **Long recordings and multiple displays** have had limited testing. See the project's compatibility notes on GitHub.

Found a bug? **About Hot Take** has a button that copies your app, system and Mac details to paste into a report, and links to the issue tracker.

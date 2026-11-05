# Hot Take vs. the feature list

Every row of `~/Desktop/Features.rtf`, in its original order (duplicates kept), checked against the repo on 2026-10-29 (branch `signing-adhoc-fallback`, build 2 changelog, `mac/Resources/Help.md`, source search, 383 passing tests).

- ✅ built
- ❌ not built (a note says why when it is hosting or an account, which is deferred)
- ⚠️ partly built, or built differently. The note says how it differs.

"Built" means the code and its synthetic tests exist. `docs/compatibility.md` lists what has not been tried by a person on a real Mac (shortcuts from other apps, Quick Record, real screenshots, rewind, the sensitive-info scan, chapters in QuickTime Player).

## Recording

| Feature | Status |
| --- | --- |
| Full-screen recording | ✅ |
| Window recording | ✅ Also records a whole app through the system picker |
| Browser tab recording | ⚠️ Browser extension only. The Mac app records the browser window (macOS can't capture a single tab) |
| Screen + camera | ✅ |
| Camera-only recording | ✅ |
| Screen-only recording | ✅ |
| Camera bubble | ✅ Move, resize, reshape, mirror, border, hide in the Studio; Save Copy draws it |
| Camera resizing | ✅ |
| Camera frames | ⚠️ Bubble shape and border color; no decorative frames |
| Camera mirroring | ✅ |
| Microphone audio | ✅ Any input; Default follows the system |
| System audio | ✅ "Computer audio" |
| Multi-monitor support | ✅ Live preview of each display, numbered |
| Custom recording dimensions | ✅ Area: drag a box |
| HD recording | ✅ Custom preset up to 2160p; no plan limits |
| Pause/resume | ✅ |
| Restart recording | ✅ |
| Live rewind | ✅ Rewind goes back 10 seconds and pauses; not on camera-only takes |
| Recording timer | ✅ |
| Recording canvas | ⚠️ Background (gradient or solid, inset, rounded, shadow) is applied in the Studio after recording, not live |
| Speaker notes | ✅ Floating window, never in the recording |
| Virtual backgrounds | ❌ Only the system's camera blur through Video Effects |
| Background noise suppression | ⚠️ Through macOS Voice Isolation. The app shows the mode and opens the menu; only the person can switch it |
| Low-light enhancement | ⚠️ macOS Studio Light through the Video Effects panel, not Hot Take's own |
| Appearance touch-up | ⚠️ Only what the macOS Video Effects panel offers |
| Drawing tools | ❌ Arrows, boxes and blurs are drawn afterward in the Studio, not while recording |
| Mouse emphasis | ⚠️ Rings at each click (Studio Mark). No cursor-path highlight |
| Sensitive-content blur | ⚠️ Manual blurs plus Find Sensitive Info (emails, phones, keys, your words) in the Studio, after recording. Can miss small or blurry text. Not live |
| Do Not Disturb | ⚠️ Leaves Notification Center out of captures. Does not turn on Do Not Disturb |
| Keyboard shortcuts | ✅ Start/stop, pause, screenshot, rewind, agent take; changeable in Settings |
| Recording controls visibility | ⚠️ The control bar is never in the video. No setting found to hide it from the screen |
| Screenshots | ✅ Screen, window or area, saved as PNG |
| Screenshot annotation | ❌ Marks work on video in the Studio only |
| Quick Record | ⚠️ Menu bar item and shortcut that start the last screen with the last settings. No desktop shortcut |

## Editing

| Feature | Status |
| --- | --- |
| Start/end trimming | ✅ |
| Mid-video trimming | ✅ Splice, remove a part, drag edges |
| Waveform editing | ✅ Audio track waveform; audio can be cut on its own |
| Split clips | ✅ |
| Video stitching | ✅ Join recordings into a new take |
| Transcript-based editing | ✅ Cut lines, Bring Back |
| Live rewind editing | ✅ Rewind (see Recording) |
| Automatic silence removal | ✅ Tighten removes pauses of 2 s or more, any language |
| Filler-word removal | ✅ "um", "uh", "er", "ah", "hmm". English only |
| Text-to-speech correction | ❌ |
| Video backgrounds | ✅ Studio Background |
| Text overlays | ✅ |
| Arrow overlays | ✅ |
| Box overlays | ✅ |
| Blur overlays | ✅ |
| Caption styling | ✅ Classic, Bold, Minimal, Highlight; top, middle or bottom; burned in |
| Thumbnail customization | ⚠️ Choose a frame from the video. Image upload not found |
| Animated GIF thumbnails | ⚠️ You can save a GIF of a stretch. The library does not use animated previews |
| Calls to action | ❌ Needs a hosted player |
| Video personalization | ❌ Needs hosting |
| Undo/revert | ✅ Undo and redo; the original is never changed |
| Video uploads | ✅ Import MP4, MOV, M4V (File ▸ Import Video or drop on the library) |
| Video downloads | ✅ Export MP4, MOV or WebM (WebM needs your own FFmpeg) |

## Hosting & Playback

| Feature | Status |
| --- | --- |
| Automatic cloud hosting | ❌ Deferred (hosting) |
| Shareable URLs | ❌ Deferred |
| Instant sharing | ⚠️ System share sheet sends the file. No link |
| Public link access | ❌ Deferred |
| Private sharing | ❌ Deferred |
| Workspace sharing | ❌ Deferred |
| Email invitations | ❌ Deferred |
| Embedded player | ❌ Deferred |
| Inline link previews | ❌ Deferred |
| Animated preview GIFs | ❌ Deferred (GIF export exists, no hosted preview) |
| Playback speed | ✅ 0.5×–2× |
| Theater mode | ✅ Also pop-out window and full screen |
| Playback quality | ❌ Not applicable: local file, no streaming renditions |
| Captions | ✅ `.vtt` file, plus burned-in captions in the Studio |
| Full transcripts | ✅ |
| Timestamp navigation | ✅ Click a transcript line |
| Chapter navigation | ✅ Watch page Chapters menu; transcript headings; chapters inside MP4/MOV files |
| Watch Later | ❌ Deferred |
| Video playlists | ❌ Folders are the closest thing |
| Viewer download controls | ❌ Deferred |
| Comment controls | ❌ Deferred |
| Reaction controls | ❌ Deferred |
| Player branding | ❌ Deferred |
| Custom video page logo | ❌ Deferred |
| Remove Loom branding | ✅ Nothing to remove; Hot Take adds no branding to videos |
| Timestamped sharing links | ❌ Deferred |
| Embed autoplay | ❌ Deferred |

## Collaboration

| Feature | Status |
| --- | --- |
| Video comments | ❌ Deferred |
| Timestamped comments | ❌ Deferred |
| Comment threads | ❌ Deferred |
| Emoji reactions | ❌ Deferred |
| Timestamped reactions | ❌ Deferred |
| Video tasks | ⚠️ The notes field lists action items from the transcript. No task tracking |
| Calls to action | ❌ Deferred |
| Share notifications | ❌ Deferred |
| Activity notifications | ❌ Deferred |
| Watch Later | ❌ Deferred |
| Team sharing | ⚠️ Hand a `.hottake` project file to a teammate (AirDrop, email, shared folder) |
| Permission-based collaboration | ❌ Deferred |

## Library & Organization

| Feature | Status |
| --- | --- |
| Personal library | ✅ |
| Shared library | ❌ Deferred |
| Team library | ❌ Deferred |
| All-company space | ❌ Deferred |
| Additional spaces | ⚠️ Folders (real Finder folders, emoji icons, nesting) |
| Folders | ✅ |
| Move videos | ✅ Drag or Move to |
| Video search | ✅ Titles, summaries, tags, folders |
| Folder navigation | ✅ |
| Tags | ✅ Written by the on-device model or by hand |
| Playlists | ❌ Folders are the closest thing |
| Video archiving | ❌ No archive; Move to Trash only |
| Video deletion | ✅ Always to the Trash, never permanent |
| Video titles | ✅ |
| Video descriptions | ✅ Summary and notes fields |
| Shared With Me | ❌ Deferred |
| Recently viewed | ❌ Not found |
| Ownership management | ❌ Not applicable without accounts |
| Workspace selection | ⚠️ New takes go into the folder being viewed |

## AI

| Feature | Status |
| --- | --- |
| Automatic titles | ✅ On-device |
| Automatic summaries | ✅ Whole long transcripts are read in parts |
| Automatic chapters | ✅ On-device, editable |
| Automatic action items | ✅ In the notes field |
| Automatic CTAs | ❌ No player to put them in |
| Filler-word detection | ✅ |
| Filler-word removal | ✅ |
| Silence detection | ✅ |
| Silence removal | ✅ |
| Transcript-based editing | ✅ |
| AI text-to-speech | ❌ |
| Multilingual transcription | ✅ Language picker, regional models; plus on-device translation |
| Transcript corrections | ✅ Edit a line; custom vocabulary and aliases |
| Transcript regeneration | ✅ Regenerate |
| Video-to-document | ⚠️ Transcript as Markdown with summary, tags and chapters. Not a written how-to document |
| Video-to-message | ❌ A copyable summary exists; no message or recap draft |
| Video-to-bug-report | ✅ Title, summary, steps with a picture each, expected, actual |
| Jira issue generation | ⚠️ Bug report copies in Jira format for pasting. No Jira connection |
| Confluence documentation | ❌ Markdown export only |
| Rovo search | ❌ Library text search only, no AI search |
| Rovo chat | ❌ |
| Meeting recaps | ❌ A summary works on any take; no recap format |
| Meeting notes | ❌ Same; no meeting template |
| Meeting recap emails | ❌ |
| Jira work updates | ❌ |
| AI feature controls | ✅ Settings switches for captions, summaries, chapters |

## AI Agents

| Feature | Status |
| --- | --- |
| Record for Agent | ✅ "For an agent" option, menu bar Quick Take, or any take's Watch page |
| Voice instruction capture | ✅ Narration is transcribed |
| Interaction capture | ✅ Click positions and times only, never which app or what you typed |
| Keyframe extraction | ✅ A picture at each click and at stretches of talk, at most 20 |
| Visited URL capture | ❌ |
| UI element selection | ❌ |
| Magic pen | ❌ |
| Console log capture | ❌ |
| Network metadata capture | ❌ |
| Generated action plans | ✅ Goal and steps from your narration, marked as the model's reading |
| Structured prompt generation | ✅ |
| Markdown prompt export | ✅ `PROMPT.md` plus a `frames` folder |
| Send to agent | ⚠️ Copies the request for you to paste into Claude Code, Codex or Cursor. Nothing is sent |
| Jira work-item creation | ❌ |

## Meetings

| Feature | Status |
| --- | --- |
| Meeting recording | ⚠️ Screen plus computer audio plus mic. No meeting detection |
| Calendar integration | ❌ |
| Automatic recording | ❌ |
| Internal-only recording | ❌ |
| One-on-one exclusions | ❌ |
| Per-meeting controls | ❌ |
| Notetaker bot | ❌ |
| Manual meeting recording | ✅ Any recording |
| Ad hoc meeting capture | ✅ Quick Record |
| Meeting library | ⚠️ Ordinary library; no meeting grouping |
| Meeting transcripts | ✅ |
| Live transcription | ❌ Transcripts are made after recording |
| Collaborative notes | ❌ Notes are single-user |
| Meeting agendas | ❌ |
| Meeting summaries | ✅ |
| Meeting action items | ✅ |
| Recap emails | ❌ |
| Confluence meeting pages | ❌ |
| Recurring meeting organization | ❌ |
| Trello task integration | ❌ |
| Meeting pause/resume | ✅ |
| Meeting chat commands | ❌ |
| Meeting access permissions | ❌ |
| Meeting recap history | ❌ |
| Meeting search | ✅ Library search |

## Analytics

| Feature | Status |
| --- | --- |
| Video view counts | ❌ Deferred (needs hosting) |
| Viewer identity | ❌ Deferred |
| Anonymous views | ❌ Deferred |
| Viewer history | ❌ Deferred |
| Viewing frequency | ❌ Deferred |
| Viewing timestamps | ❌ Deferred |
| Average completion rate | ❌ Deferred |
| CTA conversion rate | ❌ Deferred |
| Viewer email collection | ❌ Deferred |
| Engagement Insights | ❌ Deferred |
| Engagement data export | ❌ Deferred |
| Insights Hub | ❌ Deferred |
| Workspace admin insights | ❌ Deferred |
| Enterprise user reports | ❌ Deferred |
| Content activity reports | ❌ Deferred |
| Workspace activity logs | ❌ Deferred |

## Security & Administration

| Feature | Status |
| --- | --- |
| Private videos | ✅ By design: local files, no account, nothing uploaded |
| Workspace-only access | ❌ Deferred |
| Public link access | ❌ Deferred |
| Password protection | ❌ Deferred. `.hottake` files are not encrypted |
| Default privacy settings | ❌ Not applicable |
| Advanced privacy controls | ❌ Deferred |
| Public link expiration | ❌ Deferred |
| Viewer download restrictions | ❌ Deferred |
| Workspace download controls | ❌ Deferred |
| SAML SSO | ❌ |
| SCIM provisioning | ❌ |
| User roles | ❌ |
| Member administration | ❌ |
| Ownership transfer | ❌ |
| Workspace activity logs | ❌ |
| Content activity reports | ❌ |
| Custom retention policies | ❌ Nothing deletes on its own; an opt-in cleanup is not built |
| Data residency | ⚠️ Not applicable: nothing leaves the Mac |
| Admin reporting | ❌ |
| SOC 2 Type II | ❌ |
| GDPR support | ⚠️ No data is collected. No compliance claim is made |
| CCPA support | ⚠️ Same |
| EBA compliance support | ❌ |
| Uptime SLA | ❌ Not applicable |
| Dedicated support | ❌ |
| Account management | ❌ |

## Integrations

| Feature | Status |
| --- | --- |
| Slack | ⚠️ Bug report copies in Slack format. No connection |
| Microsoft Teams | ❌ Share sheet sends the file |
| Jira | ⚠️ Bug report copies in Jira format. No connection |
| Confluence | ❌ |
| GitHub | ⚠️ Bug report copies as Markdown for an issue. No connection |
| Gmail | ❌ Share sheet sends the file |
| Google Workspace | ❌ |
| Zoom | ❌ |
| Salesforce | ❌ |
| Calendly | ❌ |
| Trello | ❌ |
| Notion | ❌ |
| FigJam | ❌ |
| Figma | ❌ |
| Intercom | ❌ |
| Zendesk | ❌ |
| Dropbox | ❌ |
| GitLab | ❌ |
| Upwork | ❌ |
| Atlassian Rovo | ❌ |

## Developer Platform

| Feature | Status |
| --- | --- |
| Loom SDK | ❌ |
| Atlassian MCP | ❌ |
| Teamwork Graph CLI | ❌ |

(The app does have its own command-line checks such as `--process` and `--cut`; they are not an automation platform.)

## Platform Support

| Feature | Status |
| --- | --- |
| macOS desktop app | ✅ |
| Windows desktop app | ❌ |
| Chrome extension | ✅ Basic: screen, window or tab with optional mic and webcam, stored in the browser, with a basic editor |
| iOS app | ❌ |
| Android app | ❌ |
| Web application | ⚠️ A static web page that records locally. No hosted video management or playback |

---

# Hot Take capabilities that were not on your list

1. **Local-first and checkable.** The app refuses every web request it makes, and `--network-check` proves it. No account, telemetry, or hosted media.
2. **Auto Zoom.** The Studio zooms in on your clicks, easing in and out, as editable blocks on a Zoom track.
3. **Click rings and a picture at each click.** Used for the bug report and the agent request, and saveable on their own.
4. **Window-only capture with a styled backdrop.** A window is recorded without the menu bar or desktop, then placed on a gradient with a shadow.
5. **`.hottake` project files.** One checksummed file holds the recording, the edit and the audio, so a teammate can open it and keep editing. See `docs/hottake-file.md`.
6. **Non-destructive editing.** Autosaved drafts, a hidden recovery copy, and saved copies nested under their original as "N versions".
7. **Music and voiceover.** Background music that loops and fades, and voiceover that can replace the original audio.
8. **On-device translation** of transcripts, with translated captions saved as `.vtt` or drawn into the picture.
9. **Speech tuning.** A custom vocabulary with aliases (for example `Rovo=bravo|robo`), a choice of recognizer, and Chinese and Japanese caption wrapping.
10. **Size control.** Small, Medium, Large or Custom presets with a size estimate that updates as you change them, a custom bitrate, and a "keep original quality" option.
11. **Chapters carried inside MP4 and MOV files**, plus **Copy Timestamps** (`0:00 Title`) for video descriptions.
12. **Transcript as Markdown**, with summary, tags and chapter headings.
13. **Edit-by-transcript extras.** Find in Transcript (⌘F, ⌘G), line editing, and a Transcript panel in the Studio.
14. **Audio-only cuts** and holding the last frame, so the sound can be edited without touching the picture.
15. **Library behaving like a file manager.** Real Finder folders, emoji folder icons, drag-box selection, Join, and Import.
16. **Pop-out floating player** and full-screen playback shortcuts.
17. **Demo mode** (show Hot Take's own windows in the recording) and its default of keeping them out.
18. **Recording sounds.** Countdown tones and an end chime, with a switch.
19. **Mic Mode awareness**, with a live microphone so the system menu opens.
20. **Help center, What's New and a welcome animation**, all inside the app.
21. **Command-line checks** (`--process`, `--cut`, `--suggest`, `--splice-check`, `--studio-snapshot`) that run the same code as the app.
22. **Signing safeguards.** The bundle script clears stale permissions when the signing identity changes, and falls back to an ad-hoc signature with a warning.
23. **Camera starts before the screen**, so the bubble is in the first frame.

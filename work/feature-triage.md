# Hot Take feature triage

Source: `~/Desktop/Features.rtf` (about 270 rows, with duplicates across categories merged here). Checked against the Mac app (`mac/`) and the browser extension (`src/`) as of 2026-10-28. "Mac" means the native app, "Ext" the browser extension.

Hosting, sharing links, viewer analytics, team spaces and cloud integrations are deferred (last section), per the local-only scope.

**Doc drift found while checking:** `mac/README.md` said pause was not supported, though it is implemented (`App.swift`, pieces joined by `SegmentJoiner`). The README has since been corrected. The global hotkey it lists as missing is indeed missing.

---

## 1. Already have

| Area | Feature | Where / notes |
| --- | --- | --- |
| Recording | Full-screen, window, area (custom dimensions) | Mac New Take sheet |
| Recording | Browser tab recording | Ext only. The Mac can't (the system only sees windows); record the browser window |
| Recording | Screen + camera, screen-only | Mac presenter menu (camera off by default) |
| Recording | Camera bubble, resize, frames, mirroring | Mac Studio **Camera** (move, resize, reshape, mirror, border, hide, time-nudge) |
| Recording | Microphone, system audio, no-audio | Mac record sheet |
| Recording | Multi-monitor | Display previews with numbers |
| Recording | Up to 4K | Custom preset to 2160p |
| Recording | Pause/resume, restart, timer | Mac control bar |
| Recording | Recording canvas / background | Studio **Background** (gradient or solid, inset, rounded, shadowed) |
| Recording | Noise suppression | Through the system Mic Mode (Voice Isolation); the app shows the mode and nudges, only the user can switch it |
| Recording | Webcam background blur, low light, touch-up (partial) | System **Video Effects…** panel (blur, Center Stage, Studio Light) |
| Recording | Controls kept out of the video | Control bar and countdown never captured; draggable |
| Editing | Start/end and mid-video trimming, split clips | Studio splice, `[` / `]`, drag edges |
| Editing | Waveform editing | Audio track waveform, audio-only splice |
| Editing | Silence detection and removal | **Tighten**: long pauses (1/2/3 s), *Cut All Pauses*; also restarts |
| Editing | Text overlays, caption styling | Studio text track; 4 caption styles, 3 positions (burned in) |
| Editing | Video backgrounds | Studio Background |
| Editing | Undo/revert | Studio undo/redo; originals never changed |
| Editing | Export | MP4, MOV, WebM (WebM needs the user's FFmpeg); quality presets |
| Playback | Theater mode, pop out, full screen | Hover buttons on any video |
| Playback | Captions, full transcript, timestamp navigation | `.vtt` sidecar, burned-in captions, click a transcript line to jump |
| Library | Personal library, folders, move, folder navigation | Real folders under `~/Movies/Hot Take/` |
| Library | Search, tags, titles, descriptions | Search across title, summary, tags, folder; Info panel |
| Library | Deletion | Move to Trash only (never permanent) |
| Library | Recording destination | New takes go into the folder being viewed |
| AI | Automatic titles, summaries, tags | On-device model, Info panel sparkle buttons and *Generate All* |
| AI | Automatic action items | The **notes** field prompt lists action items, decisions and follow-ups |
| AI | Multilingual transcription | Language picker, regional models |
| AI | Transcript corrections, regeneration | Edit a line in place; *Remake*; custom vocabulary and aliases |
| AI | AI feature controls | Settings → Captions & Summary |
| Agents | Voice instruction capture | Mic + transcript |
| Meetings | Manual / ad hoc meeting recording, pause/resume, transcripts, search | It's a screen + system audio + mic recording; no calendar or bot |
| Sharing | Instant sharing (of the file) | System share sheet; `.hottake` project files for handing an editable take to a teammate |
| Security | Private videos, GDPR/CCPA posture | By construction: local files, no account, no telemetry, web requests refused |
| Platform | macOS app, Chrome extension, static web app | Mac is the most complete |

## 2. Easy additions

Small, mostly reusing code that already exists. Rough order of value.

| Feature (list name) | How | Notes |
| --- | --- | --- |
| Keyboard shortcuts + Quick Record | Global hotkey (Carbon `RegisterEventHotKey`, needs no extra permission) for start/stop/pause; menu bar item already exists | README lists this as missing |
| Mouse emphasis | Draw click rings in the Studio from the clicks `ClickRecorder` already stores (position and time) | Cursor *path* highlighting would need cursor sampling: more work |
| Arrow and box overlays | New shape kinds on the Studio text track and compositor | Shares timing, drag and resize with text |
| Blur overlays (manual) | A region on a track; Core Image blur in `StudioCompositor` | First step toward sensitive-content blur |
| Screenshots | `SCScreenshotManager` with the existing source picker; save PNG into the library folder | Annotation is in section 4 |
| Camera-only recording | Record the camera file alone as the take | Camera capture already writes its own file |
| Speaker notes | Floating notes window kept out of the capture (the app already excludes its own windows) | Teleprompter scrolling later |
| Do Not Disturb | Leave Notification Center's windows out of the capture filter | Verify on a real Mac that banners are its windows; turning on Focus itself isn't possible from an app |
| Video stitching | Multi-select in the library → Join; `SegmentJoiner` for same-format takes, Studio compositor when sizes differ | Saves as a new take |
| Import existing videos | File ▸ Import / drop an MP4 into the library, then the existing caption and summary pipeline (`--process` already does it) | |
| Playback speed | Rate menu on the player (0.5×–2×) | Not present today |
| Thumbnail choice | "Use Frame as Thumbnail" at the playhead, stored in the take's `.json` | |
| Animated GIF thumbnails / GIF export | ImageIO GIF from a range; doubles as GIF export for Slack and GitHub | |
| Appearance touch-up | Brightness/warmth/softening on the camera bubble in the Studio (Core Image) | System effects already cover live touch-up |
| Keyframe extraction | Frames at each recorded click (`AVAssetImageGenerator`) | Feeds the bug report and agent prompt below |
| Markdown export / Send to agent | Copy or save generated text as Markdown; system share sheet | No integrations, nothing sent automatically |
| Recently viewed, archive | Last-opened date in `.json`; an Archive folder | Low value |

## 3. With the on-device Apple Foundation Model

The app already uses `LanguageModelSession` for titles, summaries, tags, notes and restart detection. Constraints that shape all of these:

- **Text only.** The model reads the transcript (and anything we put in the prompt, such as click times); it doesn't see the video. Screenshots in a bug report are attached by us, not understood by the model.
- **Small context window.** Prompts currently include only a prefix of the transcript (`prompt.included` in `Summarizer.swift`), so long takes are summarized from their beginning. Chapters and documents need chunk-then-merge.
- **No `@Generable`** (it would require the full Xcode toolchain to build), so outputs are parsed from fixed text formats, as today. Revisit if building with Xcode becomes acceptable.
- Needs Apple Intelligence turned on; everything must degrade to "not available" cleanly.

| Feature (list name) | What it produces | Effort |
| --- | --- | --- |
| Automatic chapters + chapter navigation | Timestamped topic list from transcript lines (chunked); chapter list in Watch; chapter markers in exported MP4 | Medium: the main work is chunking and the chapter UI |
| Video-to-bug-report | Steps to reproduce, expected vs actual, from the transcript + click keyframes | Low–medium; strong fit for the "bug reports" use case |
| Video-to-document (and Confluence-style pages) | How-to / walkthrough Markdown with keyframes | Medium |
| Video-to-message (and recap email draft) | Short Slack/email-ready text; email opens in Mail for the user to send | Low |
| Jira issue drafts | Jira-formatted text copied out | Low. No Jira API (no network); a later opt-in integration is hosting-era work |
| Record for Agent: action plans, structured prompts | Agent-ready Markdown prompt from narration + clicks + keyframes | Medium; pairs with Markdown export |
| Meeting notes / recaps | A meeting template for the existing summary and notes fields (attendees as spoken, decisions, action items) | Low |
| Ask your library (local stand-in for Rovo search/chat) | Answer questions over transcripts: local text search picks the takes, the model answers from those excerpts with timestamps | Medium–high, because of the context window |

Not a fit for the model: filler-word and silence detection (deterministic from word timings and audio levels is more reliable; Tighten already reasons this way), and automatic CTAs (no player to put them in).

## 4. Everything else in local scope, ranked

Ranked by value for a local walkthrough / bug-report recorder against effort and risk.

| Rank | Feature | Why here | Effort / risk |
| --- | --- | --- | --- |
| 1 | Transcript-based editing | Biggest editing upgrade; line timings already exist and map onto the splice model | Medium. Line-level first, word-level later |
| 2 | Filler-word detection and removal | Common ask; builds on #1 | Medium. **Check first** whether the recognizer keeps "um"/"uh" in its output at all; if it drops them, this needs an audio-based approach |
| 3 | Live rewind | Pause already splits a take into pieces, so "back up N seconds" can truncate the last piece | Medium; needs careful camera/click sync |
| 4 | Drawing tools / magic pen during recording | Strong for walkthroughs | Medium–high: an overlay window that *is* captured, the inverse of today's exclusion |
| 5 | Sensitive-content auto blur | Natural follow-on to manual blur | Medium–high: Vision text recognition + patterns (emails, keys), tracked over time; false negatives are the risk |
| 6 | Screenshot annotation | Completes screenshots | Medium; reuse Studio shapes and text |
| 7 | Live transcription | Useful for meetings and checking captions while recording | Medium: streaming speech recognition alongside capture |
| 8 | Virtual background replacement | System already gives blur | Medium: Vision person segmentation per frame in the compositor |
| 9 | Calendar-aware meetings (discover, per-meeting rules, internal-only, 1:1 exclusions, auto-start, recurring grouping, agendas) | One feature family built on EventKit | High; consent and "recording without noticing" risks need design before code |
| 10 | Local agent access (stdio MCP / extended CLI over transcripts) | Lets Claude Code and other tools use takes | Medium; must stay local (stdio, no listening socket) to keep the no-network promise |
| 11 | Richer interaction capture (app name, keystroke markers) | Better agent prompts | Low effort, high privacy cost: the README promises clicks record only where and when |
| 12 | Text-to-speech correction | Fix a misspoken word | High; Personal Voice needs user setup, and seams are audible |
| 13 | Password-protected `.hottake` files | Safer handoff | Medium; key handling and format version bump |
| 14 | Opt-in retention (move old takes to Trash) | Disk hygiene | Low effort, but must be opt-in, app-files-only and never permanent (AGENTS.md) |
| 15 | Visited URLs, console logs, network metadata | Dev bug reports | Extension only, needs broad permissions; privacy-heavy |
| 16 | UI element selection | Agent use | High; Accessibility API, fragile |
| 17 | Video personalization | Per-recipient variants | Low value without hosting |
| 18 | Windows, iOS, Android apps | Reach | Very high; the extension already covers non-Mac recording |

## 5. Deferred: needs hosting, accounts or other people

Not ranked; revisit with the hosted collaboration work.

- **Hosting & playback:** cloud hosting, shareable/public/private/workspace links, email invites, embedded player and autoplay, link previews, playback quality, viewer download/comment/reaction controls, player branding and logo, timestamped links, Watch Later, playlists. ("Remove Loom branding": nothing to remove; Hot Take adds no watermark.)
- **Collaboration:** comments, threads, timestamped comments and reactions, video tasks, CTAs, share and activity notifications, team sharing, permissions.
- **Library:** shared/team/all-company libraries, spaces, Shared With Me, ownership transfer.
- **AI tied to services:** automatic CTAs, Rovo, Jira work updates and work-item creation, Confluence publishing.
- **Meetings:** notetaker bot, chat commands, collaborative notes, Confluence pages, Trello, access permissions.
- **Analytics:** all of it (views, viewers, completion, CTA conversion, insights, reports, activity logs).
- **Security & admin:** workspace access, link expiry, download policies, SSO, SCIM, roles, members, audit logs, data residency, SOC 2, SLA, support.
- **Integrations and developer platform:** Slack, Teams, Jira, Confluence, GitHub, Gmail, Google Workspace, Zoom, Salesforce, Calendly, Trello, Notion, Figma/FigJam, Intercom, Zendesk, Dropbox, GitLab, Upwork, Rovo, SDK, hosted MCP, Teamwork Graph. Until then, the share sheet hands the file to any of these apps.

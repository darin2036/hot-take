# Hot Take for the browser (extension and static web app)

The browser version of Hot Take: a Manifest V3 browser extension and a static web app built from the same code. It records the screen, a window or a tab with optional microphone and webcam, stores everything in the browser, and has a basic editor. Nothing is uploaded anywhere.

## What it does

- Compact browser toolbar popup with camera/mic/source-audio switches.
- Live recording timer, pause/resume, and stop from the toolbar.
- Five recent takes with direct preview links.
- Dedicated recorder window; full-page library and previews.
- Browser picker for a screen, window, or tab.
- Optional microphone, available source audio, and a baked-in circular webcam overlay.
- Pause/resume, elapsed active time, and a 30-minute automatic stop.
- Sequential IndexedDB chunk storage with a bounded pending-write queue.
- Local library, preview, rename, MP4 download (WebM fallback), and explicit deletion.
- Recovery of committed bytes after an interruption; interrupted containers may not play.
- A per-origin Web Lock prevents multiple recorder owners in one browser profile.

Webcam composition is experimental: keep the recorder visible. The browser can throttle background canvas rendering. The native picker remains authoritative; source audio and resolution depend on the browser, source, OS, and permissions. Video duration metadata and seeking across external players still need validation.

## Run locally

Use Node.js 24 LTS and npm.

```sh
npm ci
npm run dev
```

Open the localhost URL printed by the dev server in a desktop browser. Click **New recording**, then **Choose screen & record** in the compact recorder window. Choose a source and keep that recorder open. Stop, preview, and download from **Your takes**. Camera, microphone, and source audio start on by default; subsequent choices are remembered locally. When a device is denied, disable it and retry, or fix its permission.

## Load the browser extension

```sh
npm ci
npm run build
```

1. Open `chrome://extensions` and enable Developer mode.
2. Choose **Load unpacked** and select this project's `dist` folder.
3. Pin Hot Take and click its toolbar icon to open the popup.
4. Choose camera/microphone options and click **New recording**.
5. In the compact recorder window, click **Choose screen & record**. the browser requires this direct click to show its source chooser.
6. Reopen the toolbar popup to pause, resume, or stop. Click a recent take to open its full-page preview.

If you loaded the previous build, rebuild and click **Reload** on Hot Take in `chrome://extensions`. Finish any recording before reloading an extension.

The extension requests no additional the browser permissions and has no host permissions or content scripts. Screen, microphone, and camera access use browser consent prompts. Incognito is disabled. Closing the recorder page stops capture; dismissing the toolbar does not.

## Self-host

Run `npm run build` and serve the **contents of `dist/`** from any static HTTPS server. Relative asset paths support subdirectories. HTTPS is required except on localhost. No Node server is needed in production. Keep it on a dedicated origin: other scripts served from that same origin can access its local browser storage.

This hosts the recorder UI, not a video-sharing service. Media stays in each visitor's browser. To share a take today, download it and place it in your own storage or upload it manually to Drive. Localhost, the hosted site, and the extension each have separate libraries. Host/server access logging is controlled by whoever operates the host.

## Storage and recovery

Media chunks and metadata are committed transactionally to IndexedDB. The recorder requests persistent storage where supported, but clearing site data, deleting a browser profile, or uninstalling the extension can remove recordings. **Download anything you want to keep.** Downloads never automatically remove local bytes.

Recording stops on a storage error or when its pending write queue exceeds 32 MiB. Preview/download currently assemble a Blob from stored chunks; large-recording memory use has not been benchmarked. There is a startup free-space check, but no continuous quota forecast. Recovery preserves bytes, not a guarantee of playable video.

## Editing and recording details

Camera/microphone consent is handled by the browser and reused when the browser retains the grant. Both enabled devices use one combined request, only when recording starts. One-time grants, revocation, cleared site data, and OS policy can require consent again. the browser requires a source selection for every screen recording; source audio still depends on the chosen surface and the browser chooser. No extra application permission dialog is shown.

## Basic editing

Click a recording's scissors icon in the library. Drag the selection handles (or set From/To in seconds), then **Trim to selection** or **Remove selection**. Multiple removals join the remaining sections in their original order. **Preview edit**, **Undo**, and **Reset** are available. **Save copy** creates a separate recording; the original is unchanged. This is a single-recording cutter, not a multi-video timeline.

The initial editor re-encodes locally (MP4 where the browser supports it, otherwise WebM) in real time. Keep its tab visible during saving. Export is not lossless or guaranteed frame-accurate; it can slightly soften video and cut boundaries can vary by a few frames. Cancel removes only the unfinished copy. Camera/mic access is not requested for editing. Long-recording resource and A/V sync checks remain release gates.

Recording starts after a 3–2–1 countdown. Restart discards the current take and counts down again using the same screen and inputs. The browser Document Picture-in-Picture opens compact, always-on-top controls when Record is clicked. Closing those controls leaves the recording running; use Float controls in the recorder to reopen them. Keep the recorder window open. If Picture-in-Picture is unavailable or denied, use the recorder or extension toolbar controls.

The editor supports text overlays: Add text, drag it on the video (or use arrow keys), set From/To in source-video seconds, and choose Small/Medium/Large and a color. Text is burned into Save copy output; originals stay untouched. Overlay timing follows the source through cuts. Editing changes are kept in memory until exported.

Audio editing: use Add audio (or drop a file onto the audio controls), set its start in edited-video seconds, and adjust volume. Record voiceover plays the kept video segments while capturing the microphone; completing a voiceover mutes the original audio by default. One imported track and one voiceover can be mixed together. Stop keeps a partial voiceover; Cancel preserves any previous one. Added tracks end naturally or at the end of the video. Finish cuts before dubbing: later cuts change the video beneath audio positioned on the edited timeline. Audio edits support Undo and Reset and are included in Save copy. Imported/recorded audio remains in memory until exported.

## Icons

Interface icons use [Lucide](https://lucide.dev), pinned via `lucide-static` and bundled as local inline SVGs. No icon CDN, font download, or runtime service is used. See [Lucide / Feather license notices](licenses/lucide-LICENSE). Hot Take's original code remains MIT; third-party icons retain their upstream licenses. The custom Hot Take brand mark remains separate from the interface icon set.

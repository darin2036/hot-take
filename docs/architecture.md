# Architecture

One TypeScript UI builds to static files used both by HTTPS hosting and the Manifest V3 extension. The toolbar action opens popup.html. No service worker is needed in this build. The popup launches or focuses a dedicated recorder window; index.html defaults to the full library. A view query parameter selects recorder/library/studio, and a recording ID can deep-link a preview.

`src/main.ts` owns UI lifecycle and the active recording, calls `getDisplayMedia()` synchronously from the trusted click, and holds a Web Lock until finalization. The source picker may appear before a competing recorder is rejected; rejected streams are stopped. `src/capture.ts` acquires optional devices, mixes audio through Web Audio, and composites an optional webcam into canvas video. Without webcam, the source video track is encoded directly. All acquired tracks and audio resources are disposed on failure/stop.

`MediaRecorder` emits MP4 (H.264/AAC) chunks where the browser supports it, falling back to WebM; `supportedMime` in `src/capture.ts` holds the preference order. Chunks arrive approximately every second. A serialized promise queue commits each Blob with metadata via `src/storage.ts`; more than 32 MiB pending stops capture. Stop waits for the final data event and queued commits before publishing a ready recording. A failed write leaves interrupted metadata and previously committed bytes.

IndexedDB has recording rows and ordered `[recordingId, sequence]` chunk keys. A crashed owner leaves `recording` status. The explicit Recover action takes the same Web Lock before marking it interrupted. Browsers release locks when pages die. Recovery does not pretend truncated containers are healthy.

Preview/download read stored chunks into a Blob; this is a known large-file memory benchmark gate. Library titles are rendered with textContent. There are no tokens or remote APIs in this build. Relative build paths allow static hosting below a URL prefix. Hosted and extension storage are separate origins.

The actual scope and evidence are in roadmap.md and compatibility.md.

## Toolbar control protocol

`src/control.ts` uses same-origin BroadcastChannel with schema version, request ID, and owner ID. Only a busy recorder responds to status requests. Commands target the current owner and use explicit pause/resume operations, so retries cannot toggle the state twice. Stop acknowledges the saving state before finalization; the next status request discovers completion. A missing owner times out and the popup does not pretend controls succeeded. Metadata remains recoverable in the library. No media crosses this channel.

Popup state is queried from the live owner when opened and on a short polling interval, not cached in a worker. Closing the popup releases its transient channels while the recorder remains alive. Poll replies begun before a command are ignored to avoid stale UI. An idle recorder can accept updated camera/mic choices when reused; active devices cannot be changed by that setup message.

`src/navigation.ts` uses runtime.getContexts to discover only this extension's documents, focuses an existing recorder, and reuses a library tab for preview. No broad tabs/host permission is added. A hosted build uses a named recorder window and normal library tabs. Popup and recorder share the base control typography/focus styles; the popup adds compact layout only.

## Mac app

The Mac app is a SwiftPM package in `mac/` (macOS 26+). `RelaytakeCore` holds all pure logic (file naming, metadata, captions, the cut/splice model, Studio project, zoom and background geometry, prompts) and the AVFoundation-based composer, so it is unit-tested without a screen. The `Relaytake` target is the SwiftUI/AppKit app: ScreenCaptureKit capture into the system MP4 writer, a click recorder, the library, the Studio, and the on-device captioning and writing pipeline. `Packages/PlainspokenSpeech` wraps the system's speech APIs and the offline network guard.

- **Recording** is owned by a single `ScreenRecorder` (ScreenCaptureKit's recording output), so files have correct duration and seeking. A `ClickRecorder` listens for click positions and times; nothing else.
- **Studio** edits are a pure value, `StudioProject` (cuts and splices, text, captions, zooms, background, music and voiceover), with snapshot undo. Previews and saved copies come from the same `StudioComposer`, so what you see is what you save: audio is mixed in an `AVMutableComposition`, and text, captions, backdrop and zoom are drawn by a custom `AVVideoCompositing` (Core Image) because Core Animation's video tool returned blank frames on the test machine.
- **Files are the database:** each take is `name.mp4` plus optional `name.vtt` and `name.json`; folders are real folders. Versions saved from the Studio record `derivedFrom` in their `.json`.
- **No network:** `NetworkGuard` (a URLProtocol) refuses web requests process-wide.

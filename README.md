# Hot Take

**Show it. Say it. Keep it yours.**

Hot Take is a free, open-source screen recorder for quick walkthroughs, bug reports and asynchronous updates, with one rule: **your recordings stay on your machine.** No account, no subscription, no telemetry, and no media server run by this project.

It comes in two forms that share the same idea:

| | What it is | Best for |
| --- | --- | --- |
| **[Hot Take for Mac](mac/README.md)** | A native menu-bar app. Records the screen, a window or an area to MP4, then captions, titles, summarizes and edits it with the system's on-device models. | Everyday use on a Mac. The most complete version. |
| **[Hot Take for the browser](docs/browser-extension.md)** | A Manifest V3 extension and static web app. Records a screen, window or tab with optional microphone and webcam into the browser's own storage, with a basic editor. | Other platforms, or when you cannot install an app. |

> **Status: 0.1 pre-release.** Both versions work and are tested, but they have been tried on very few machines. [docs/compatibility.md](docs/compatibility.md) lists exactly what has and has not been verified. Cloud upload and sharing links are not built yet (see the [roadmap](docs/roadmap.md)).

## Why

- **Local first.** Recordings are ordinary files on your Mac (or chunks in your browser's storage). Nothing is uploaded unless you copy a file somewhere yourself.
- **Private by construction.** There is no analytics code, no remote script and no hosted media. The Mac app refuses all web requests, and you can verify that yourself (`--network-check`). See [docs/privacy.md](docs/privacy.md).
- **Open and hackable.** MIT licensed, small codebase, no third-party runtime dependencies in the Mac app.
- **Smart where it helps.** On a Mac with on-device intelligence, captions, titles, summaries and suggested cuts are made on-device. Without it, you still get a recorder and an editor.

## What the Mac app does

- **Record** a whole screen, a single window (without the menu bar and desktop around it), or an area, with a microphone choice, a file-size choice and optional computer audio. A small control bar can be dragged out of the way and is never in the video.
- **Watch, search and organize** takes in a library with folders (emoji icons supported), versions nested under their original, and a transcript you can click to jump around.
- **Caption and summarize on-device:** timed captions (`.vtt`), a title, summary, tags and notes, written by the system's speech and language models frameworks with your own custom vocabulary.
- **Edit in the Studio:** splice and trim, drag edges, add text, music and voiceover, burn in captions, put a window on a styled background, and zoom in automatically on your clicks. Edits are non-destructive; saving makes a new copy.
- **Compress and export** to MP4, MOV or WebM (WebM needs your own FFmpeg).

Details and limits are in [mac/README.md](mac/README.md).

## Quick start

### Mac

You need macOS 26 or later and the Swift toolchain (the full developer tools, or `xcode-select --install`).

```sh
git clone <this repository>
cd <the cloned folder>/mac
./scripts/bundle.sh
open "build/Hot Take.app"
```

The first time, the system asks for Screen Recording (and Microphone if you record your voice). See [mac/README.md](mac/README.md#build-and-run) for signing and permissions, which matter more than you would expect.

### Browser extension

You need Node.js 24 and npm.

```sh
npm ci
npm run build
```

Then open your browser's extensions page (`chrome://extensions`), enable developer mode, choose **Load unpacked**, and select the `dist` folder. To try it as a web page instead, run `npm run dev`. More in [docs/browser-extension.md](docs/browser-extension.md).

## Repository layout

| Path | What is there |
| --- | --- |
| `mac/` | The Mac app: a Swift package with the app (`Sources/Relaytake`), a pure-logic library (`Sources/RelaytakeCore`), tests, scripts, and the vendored on-device speech package (`Packages/PlainspokenSpeech`). |
| `src/`, `public/`, `*.html` | The browser extension and static web app (TypeScript, built with a standard bundler). |
| `tests/`, `scripts/` | Browser checks, build, validation and icon scripts. |
| `docs/` | Architecture, privacy, roadmap, the verification log and design decisions. |
| `artwork/` | The icon master and notes. |

Some internal names (the `Relaytake` Swift module and folder names, the `org.relaytake.mac` bundle identifier) are kept as they are so existing installs keep their settings and permissions.

## Development

```sh
# browser extension and web app
npm ci
npm run typecheck && npm test && npm run build

# Mac app
cd mac
./scripts/test.sh
swift build -c release
```

Continuous integration runs the web tests and build on every push; the Mac job needs a macOS 26 runner. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to propose changes and the project's ground rules ([AGENTS.md](AGENTS.md) lists the invariants: local recording without sign-in, no telemetry or remote code, cloud features only with narrow scopes and no automatic sharing or deletion).

## Roadmap

Next: more real-device testing, then opt-in cloud-storage upload with the narrowest permissions (access only to files the app creates, no automatic sharing, never permanently deleting your files). See [docs/roadmap.md](docs/roadmap.md).

## Independence

Hot Take is an independent project. It is not affiliated with or endorsed by any other product or company. It is not a replacement for hosted review, analytics or collaboration services.

## License and credits

[MIT](LICENSE) © 2026 Darin Laframboise. Original code, documentation and artwork in this repository are MIT licensed. Third-party components keep their own licenses: see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

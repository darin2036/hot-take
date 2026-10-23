# Third-party notices

Hot Take's own code, documentation and artwork are released under the [MIT license](LICENSE). This file lists everything else that ships with, or is used to build, the project.

## Shipped in the browser extension and web app

| Component | License | Use |
| --- | --- | --- |
| [Lucide](https://lucide.dev) icons (via `lucide-static`) | ISC | A handful of interface icons, copied into the built JavaScript as inline SVG. No icon CDN, font or runtime download. Full text: [`licenses/lucide-LICENSE`](licenses/lucide-LICENSE). |

No other third-party code is bundled into the built extension.

## Shipped in the Mac app

The Mac app contains **no third-party code**. It uses The system frameworks (SwiftUI, AppKit, AVFoundation, ScreenCaptureKit, Speech, Foundation Models, Core Image), which are part of macOS and are not redistributed.

| Component | License | Use |
| --- | --- | --- |
| `mac/Packages/PlainspokenSpeech` | MIT (see its [LICENSE](mac/Packages/PlainspokenSpeech/LICENSE)) | On-device speech recognition helpers (engines, language models, vocabulary, offline guard). Written by the same author, kept here as its own package; it depends only on system frameworks. |

## Optional tools you provide yourself

- **FFmpeg** (optional): WebM export in the Mac app uses an FFmpeg you install separately with `libvpx-vp9` and `libopus`. FFmpeg is **not** bundled or distributed by this repository, and its own license (LGPL or GPL, depending on how it was built) applies to your copy. Anyone who packages Hot Take together with FFmpeg must include FFmpeg's notices and meet its license terms.

## Used only to build and test (not shipped)

| Component | License |
| --- | --- |
| TypeScript | Apache-2.0 |
| Vite | MIT |
| Vitest | MIT |
| fake-indexeddb | Apache-2.0 |
| @types/chrome | MIT |
| lucide-static | ISC |

Their own dependencies are listed in `package-lock.json`. Run `npm ls --all` for the full tree.

## Names

Product, company and platform names mentioned in this repository belong to their owners and are used only to describe what Hot Take runs on or works with.

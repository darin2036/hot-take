# Third-party notices

Hot Take's own code, documentation and artwork are released under the [MIT license](LICENSE). This file lists everything else that ships with, or is used to build, the project.

## Shipped in the browser extension and web app

| Component | License | Use |
| --- | --- | --- |
| [Lucide](https://lucide.dev) icons (via `lucide-static`) | ISC | A handful of interface icons, copied into the built JavaScript as inline SVG. No icon CDN, font or runtime download. Full text: [`licenses/lucide-LICENSE`](licenses/lucide-LICENSE). |

No other third-party code is bundled into the built extension.

## Shipped in the Mac app

The Mac app's recording, editing, captions and everything in `RelaytakeCore` use no third-party code. Only the on-device voice (see the table) brings in outside code, linked into the app target alone. The app also uses the system frameworks (SwiftUI, AppKit, AVFoundation, ScreenCaptureKit, Speech, Foundation Models, Core Image), which are part of macOS and are not redistributed.

| Component | License | Use |
| --- | --- | --- |
| `mac/Packages/PlainspokenSpeech` | MIT (see its [LICENSE](mac/Packages/PlainspokenSpeech/LICENSE)) | On-device speech recognition helpers (engines, language models, vocabulary, offline guard). Written by the same author, kept here as its own package; it depends only on system frameworks. |

The on-device voice for voiceovers (Settings ▸ Voice) is built from these, all pinned to exact versions in `mac/Package.swift` and `mac/Package.resolved`. Their license texts are in [`licenses/`](licenses/).

| Component | License | Use |
| --- | --- | --- |
| [kokoro-ios](https://github.com/mlalma/kokoro-ios) 1.0.11 | MIT | Runs the Kokoro speech model with MLX. [`licenses/kokoro-ios-LICENSE`](licenses/kokoro-ios-LICENSE) |
| [MisakiSwift](https://github.com/mlalma/MisakiSwift) 1.0.6 | Apache-2.0 | Turns English text into the sounds to speak, with its bundled pronunciation dictionaries. [`licenses/MisakiSwift-LICENSE`](licenses/MisakiSwift-LICENSE) |
| [MLXUtilsLibrary](https://github.com/mlalma/MLXUtilsLibrary) 0.0.6 | Apache-2.0 | Helpers used by the two above. [`licenses/MLXUtilsLibrary-LICENSE`](licenses/MLXUtilsLibrary-LICENSE) |
| [MLX Swift](https://github.com/ml-explore/mlx-swift) 0.30.2 (with the MLX C++ library it builds) | MIT | Apple's array framework, run on the GPU. [`licenses/mlx-swift-LICENSE`](licenses/mlx-swift-LICENSE) |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) 0.9.21 | MIT | Reads archives for MLXUtilsLibrary. [`licenses/ZIPFoundation-LICENSE`](licenses/ZIPFoundation-LICENSE) |
| [swift-numerics](https://github.com/apple/swift-numerics) 1.1.1 | Apache-2.0 | Numeric types used by MisakiSwift. [`licenses/swift-numerics-LICENSE`](licenses/swift-numerics-LICENSE) |

**Not bundled; downloaded by the person on request:** the [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) model weights and voices (Apache-2.0), as converted by [mlx-community](https://huggingface.co/mlx-community/Kokoro-82M-bf16). The model's page says it was trained on permissive or non-copyrighted audio, and credits two CC BY datasets: [Koniwa](https://github.com/koniwa/koniwa) `tnc` (CC BY 3.0) and [SIWIS](https://datashare.ed.ac.uk/handle/10283/2353) (CC BY 4.0), plus synthetic data from contributors. Check that page for the current terms before redistributing the weights.

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

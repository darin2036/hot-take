# Privacy

Hot Take sends no media, titles, captions, diagnostics or analytics to the maintainer or anyone else. It has no cloud storage, no accounts of its own and no analytics code. Two optional connections exist, both started by you: a one-time download of the on-device voice, and an ElevenLabs voiceover if you choose it (below). Screen capture can include private information and notifications; you choose what to record, and recordings stay where you put them.

## Mac app

- **Where things live:** recordings, captions (`.vtt`), notes and metadata (`.json`) are ordinary files in `~/Movies/Hot Take/` (or a folder you pick). Deleting a recording moves it to the Trash, never permanently.
- **No network:** the app refuses every web request it makes (a URL-protocol guard installed at launch; `--network-check` proves it), except the two below, neither of which runs until you start it.
- **Voice on this Mac (default):** Settings ▸ Voice offers a one-time download of Kokoro, an open speech model (Apache-2.0), and ten English voices (about 330 MB) from `huggingface.co`, pinned to one revision of `mlx-community/Kokoro-82M-bf16`. Each file's size and SHA-256 are checked before it is kept, and a file that does not match is deleted. The files are stored in `~/Library/Application Support/Hot Take/Kokoro`, and **Remove…** deletes that folder. Hugging Face sees an ordinary download (your IP address and the file names). After that, speaking a line runs on your Mac's GPU and sends nothing anywhere. Third-party code that runs it (MLX, Kokoro, MisakiSwift) is listed in `THIRD_PARTY_NOTICES.md`.
- **ElevenLabs voiceover (optional):** Settings ▸ Voice takes an API key from your own ElevenLabs account. The key is kept in your Mac's Keychain and is sent only to `api.elevenlabs.io`, as a header. When you ask for a voiceover (or, if you allowed it, when an agent's edit does), the words of the lines to be spoken are sent to ElevenLabs over HTTPS, and your ElevenLabs plan is charged for the characters. Nothing else is sent: no recording, audio, transcript beyond those lines, titles or identifiers. ElevenLabs' own terms and privacy policy govern what it does with the text. The audio it returns is saved in the take's hidden `.hot-take-audio` folder. Signing out removes the key; local agents never see it and may speak at most 5,000 characters per edit.
- **On-device AI:** captions use the system's speech framework and titles, summaries and suggested edits use the system's language models, both running on the Mac. the system itself may download the system's speech language models the first time a language is used; that is the system, not this app.
- **Translation:** the Transcript tab's Translate menu uses the system's Translation framework, which translates on the Mac. The system may download a language the first time, and Apple's documentation says it may collect API usage and performance metrics (including this app's bundle ID and the source and target languages) but not the original or translated text. This app sends no text anywhere. Translations are stored in the recording's `.json`.
- **Click positions:** to propose zooms, the app notes *where* and *when* you click during a recording (a position inside the recorded picture and a time), and stores them in the recording's `.json`. It never records which app or element was clicked, keystrokes, or anything typed. Delete the file's notes to remove them.
- **Window list:** the record sheet lists open windows to draw previews. It is read for that purpose only and nothing is recorded until you press Start.
- **Permissions:** Screen Recording, Microphone if you record your voice, and Camera if you choose one, are asked for by the system. Revoke them in System Settings → Privacy & Security.
- **Encryption:** files are not encrypted by the app; use FileVault.

## browser extension and web app

Recordings and titles stay in IndexedDB in the current browser profile and origin until deleted or browser data is cleared. Download creates a local file and does not remove the library copy; deleting a library item removes its metadata and stored chunks, not downloads. Nothing is scheduled for cleanup.

The extension has no host permissions, content scripts or additional browser permissions. Its toolbar action opens a small popup that launches a dedicated recorder window; recording controls exchange small same-origin messages while media stays in IndexedDB. Browser and OS prompts govern screen, microphone and camera access. Library data has no extra application encryption.

Anyone who self-hosts the static app controls their own web server, logs and delivered code: use a dedicated, trusted origin. Files you upload or share yourself are subject to the destination's rules.

# Privacy

Hot Take sends no media, titles, captions, diagnostics or analytics to the maintainer or anyone else. It has no cloud integration, no accounts and no analytics code. Screen capture can include private information and notifications; you choose what to record, and recordings stay where you put them.

## Mac app

- **Where things live:** recordings, captions (`.vtt`), notes and metadata (`.json`) are ordinary files in `~/Movies/Hot Take/` (or a folder you pick). Deleting a recording moves it to the Trash, never permanently.
- **No network:** the app refuses every web request it makes (a URL-protocol guard installed at launch; `--network-check` proves it).
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

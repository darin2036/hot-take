# Milestone ledger

- [x] 0.1 source scaffold, MIT license, static and MV3 builds.
- [x] Extension toolbar popup, live remote controls, recent takes, recorder window and full library.
- [x] Unpacked-extension synthetic capture/control/preview flow, popup reopen and recorder reuse.
- [x] Local capture implementation, audio mixing, webcam composition, pause/stop.
- [x] Durable chunk transactions, bounded writer queue, explicit recovery and library.
- [x] Synthetic-browser recording, preview, download, pause, and reload checks.
- [x] Mac app: system-framework MP4 recorder, on-device captions, titles and summaries, library with folders and versions, and a Studio (splice, text, captions, music, voiceover, background, auto zoom). Exercised on one Mac only; see docs/compatibility.md for what is and is not verified.
- [ ] M0 exit: actual tab/window/screen on target OS; camera/mic tests; codec and cloud-storage feasibility.
- [ ] M1 exit: finite MP4/WebM duration/seekability (MP4 is fragmented; verify in common players, chat tools and cloud storage); minimized composition; 30-minute memory/A-V profiling; quota fault injection; device selectors, preflight, countdown, persisted preferences, live input-loss handling and accessibility audit.
- [ ] M2: cloud-storage OAuth configuration, narrowest file-only scope, account binding, app folder, bounded resumable transport, duplicate reconciliation and failure tests.
- [ ] M3: second-account recipient playback and native timestamp review evidence.
- [ ] M4: opt-in best-effort 14-day trash, Keep/Extend and cancellation-race tests.
- [ ] M5: cross-platform matrix, private security reporting, name review, store/OAuth readiness, public release.

No milestone beyond the local preview is declared complete. Cloud credentials cannot substitute for implementing and testing M2. Do not enable cleanup before upload reliability. Do not present a link as shared access.

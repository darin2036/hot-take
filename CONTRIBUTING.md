# Contributing

Thank you for helping. Hot Take is small and local-first, and the aim is to keep it that way.

## Ground rules

These come from [AGENTS.md](AGENTS.md) and are the reason people can trust the app:

- Local recording must always work **without signing in**.
- No telemetry, analytics, hosted media infrastructure or remotely loaded executable code.
- Cloud features are future work and must stay narrow: uploads limited to files the app creates, account-bound and resumable, **no automatic public sharing**, and cleanup that is opt-in, limited to files the app made, and never permanently deletes anything. Please discuss these in an issue before writing code.
- Do not claim device, store or native-capture validation from synthetic tests. If you could only test with generated media, say so.

## Setting up

**browser extension and web app** (Node.js 24, npm):

```sh
npm ci
npm run typecheck && npm test && npm run build
```

**Mac app** (macOS 26+, Swift 6.2; the full developer tools or the command line tools):

```sh
cd mac
./scripts/test.sh                      # core tests
./scripts/bundle.sh                    # builds build/Hot Take.app
(cd Packages/PlainspokenSpeech && ./scripts/test.sh)   # the speech package (uses the real recognizer)
```

Some internal names (the `Relaytake` Swift module, `org.relaytake.mac`) are kept as they are for compatibility with existing installs; please leave them alone in unrelated changes.

## Making a change

- Keep changes focused. In the pull request, say what changed, what you ran, and what you could not test.
- Add tests for logic (cut and splice rules, naming, metadata, storage and recovery, timing). The Mac app's pure logic lives in `mac/Sources/RelaytakeCore` so it can be tested without a screen.
- For anything that touches capture, permissions, or the UI, test by hand on a real Mac or browser and note it. Real devices and native prompts cannot be covered by synthetic tests.
- Use generated media and test accounts only. **Never attach real recordings, credentials, browser profiles, token-bearing URLs or private names** to issues, pull requests or test fixtures.
- Update the relevant README or `docs/` page, and add an honest entry to [docs/compatibility.md](docs/compatibility.md) saying what you verified and how.

## Licensing

By contributing you agree that your contribution is licensed under the project's [MIT license](LICENSE). Do not include code or assets you do not have the right to relicense under MIT, and add any third-party material to [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Please follow the [code of conduct](CODE_OF_CONDUCT.md).

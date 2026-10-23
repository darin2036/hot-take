# Hot Take identity

An original flame mark on a blue-violet tile (the same flame the Mac menu bar uses). Released under the repository's MIT license.

- `hot-take-master.png` is the 1024 × 1024 master (the flame on the tile, with transparent margins for the Mac app icon). `relaytake.svg` is the earlier clapperboard mark, kept for reference.
- `../public/favicon.svg` is the tightly framed web variant, a 256-pixel PNG wrapped in an SVG.
- `../public/icons/` contains the browser extension sizes.
- `../mac/Resources/AppIcon.icns` includes 16, 32, 128, 256 and 512 point representations at 1× and 2×.
- `../mac/Resources/AppIcon.png` is the 1024-pixel PNG master.

Regenerate on a Mac with `python3 scripts/build-icons.py`. It uses built-in `sips` and `iconutil`, with no package dependencies. The Mac bundle script copies the ICNS and declares `CFBundleIconFile` before signing. Reopen the newly built app to pick up the icon; a running app may retain its previous icon until relaunched.

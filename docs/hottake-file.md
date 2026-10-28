# The `.hottake` file

A `.hottake` file is one self-contained file holding a recording, the Studio edit made to it and everything the edit uses (audio, captions, notes), so a teammate can open it in Hot Take and carry on editing. Use **Save Project** in the Studio to make one and **File ▸ Open Hot Take File…** (or double-click) to open one. Opening adds a new take to the library and never replaces an existing one.

It is Hot Take's own container, not a ZIP, and it is **not encrypted**. It is a file you give someone directly (AirDrop, a shared folder, email); Hot Take does not upload it anywhere.

## Layout

```
"HOTTAKE1"  format version (UInt32, little endian)      header, 12 bytes
blob, blob, …                                           media and data, back to back
manifest (JSON)                                         format, app, title, revision, saved date, and per blob:
                                                        id, role, suggested name, offset, length, SHA-256
manifest offset, manifest length (UInt64 × 2),
manifest SHA-256 (32 bytes), "HTKEND!!"                 footer, 56 bytes
```

The manifest is at the end so a file is written in one pass. Roles: `video`, `screenOriginal`, `cameraOriginal`, `metadata`, `captions`, `draft` (the edit, the same JSON the Studio keeps as hidden crash recovery) and `audio`.

## Rules the reader follows

- Nothing in a file is a path. Blobs are found by offset and the app chooses where each is written; a blob's name is only used for a safe extension. Audio in the edit is named `hottake-media:<blob id>`, never by a path from the sender's Mac.
- The footer, the manifest checksum, every blob's range and every blob's SHA-256 are checked. A damaged or cut-short file is refused with a plain message and leaves nothing in the library.
- A file with a newer format version is refused with an "update Hot Take" message. Unknown roles are refused. Blobs read into memory (the edit, metadata) are capped.
- A file is written to a temporary file beside the destination and moved into place, so a failed or cancelled save never replaces a good file.
- The `derivedFrom` link in the notes is cleared on import, because the original it names is not in the recipient's library.

## Not done

Merging two people's edits to the same project, streaming media from the file without unpacking it, and any upload or link sharing are not built. The revision number only counts saves from the same take on one Mac while its draft exists.

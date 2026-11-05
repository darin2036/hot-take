---
name: demo-recording
description: Plan, record and edit a screen demo of an app with Hot Take on this Mac, driving the app yourself. Use when asked to record a demo, walkthrough or product video; produces a tightened video with zooms and captions plus a voice-over script. Needs Hot Take's "Let local agents control recording" setting turned on.
---

# Record a demo with Hot Take

You drive the app being demoed (computer use, Playwright, AppleScript, whatever you have). Hot Take records and edits, through the `hottake` command or its MCP tools (`hottake mcp`); it can also click and type for you if the person allows it. Nothing leaves this Mac.

Before anything: run `hottake status`. If it says it cannot reach Hot Take, ask the person to open Hot Take and turn on **Settings ▸ Recording ▸ Let local agents control recording**. Do not try to turn it on yourself.

Then find your way around:

- `hottake displays` lists every display with its number, name, and position and size in points. Use the number for `start --display N`, and `--display N` on `click`, `move` and `drag` to aim at a point from that display's top-left corner.
- `hottake screenshot [--display N]` saves a picture of a screen without recording and prints the PNG's path, so you can look at what you are driving. It only ever goes in a private folder on this Mac, cleared after a day.
- `hottake window --display N` puts Hot Take's own window on that display (useful when Hot Take is the app being demoed).
- If you have no other way to click and type, `hottake move`, `click`, `drag`, `key` and `type` send real mouse and keyboard events (so the pointer moves on screen and Hot Take notes each click for zooms and rings). They work only after the person also turns on **Also let agents use the mouse and keyboard**; if they refuse, ask for that switch and do not look for another way around it. Your terminal or agent app may also need Accessibility permission, which only the person can grant.

## 1. Propose, then wait

Write a short plan and show it to the person before recording:

- **Audience and length** (default: someone new to the app, 60–90 seconds).
- **Beats**: 4–8 steps. Each has a short **name** (it becomes a marker and a chapter), what you will click or type, and the one thing the viewer should notice.
- **Setup**: which display to record, what must already be on screen or logged in, and any private data that must not appear (names, emails, keys). If something sensitive is unavoidable, plan a `blur` mark.
- **Check the screen first**: run `hottake preflight --display N` (add `--term WORD` for a name, client or hostname to watch for). It lists the apps with windows on that display and warns about text that looks sensitive. Ask the person to clear the screen, or choose another display, before you record. Do not take your own screenshot of a display you have not checked; it may show personal content.
- **Hot Take as the subject**: Hot Take can run one recording at a time, so a demo of Hot Take cannot show starting a take (⌘N, **New Take** and the record sheet end or block the recording). Show the Record menu and the library instead, and do not press ⌘N while recording. While an agent's recording runs, ⌘N is ignored on purpose.
- **Open menus are not recorded**: a recording of a display shows a menu's title highlighted in the menu bar but not the menu that drops down. Do not plan a beat around showing a menu's items; show a window or sheet instead, or say what is in the menu in a caption.
- **Narration**: one or two plain sentences per beat, written to be read aloud at about 2.5 words a second. If nobody will speak it, the same lines can be the captions (see Edit): ask the person which they want, voice-over or captions, or both.

Wait for a yes or changes. Do not record before that.

## 2. Rehearse without recording

Walk the beats once with no recording. Fix anything that fails, pops up unexpectedly (notifications, update prompts, cookie banners) or is slow. Put the app back in its starting state.

## 3. Record

1. `hottake start --display N`. It returns once recording has really begun, after the countdown. The recording bar stays on screen.
2. For each beat, run `hottake marker "Beat name"` just before the first action, then do it. Move the pointer deliberately and click on the thing you mean: Hot Take notes clicks, and zooms aim at them.
   If you started a step a moment before marking it, `hottake marker "Beat name" --back 3` places the marker three seconds earlier.
3. When the app is slow (loading, installing, waiting for a response), mark it: `hottake marker "Waiting: report"` before and `hottake marker "Done: report"` after. These are what you cut.
4. `hottake stop`. It saves the take and prints its file, length and markers.

If a step goes wrong, do not stop. Run `hottake retake "Beat name"` (the name of the step you are redoing) and do the step again. The edit then cuts the failed attempt for you, and the retake keeps the step's name, chapter and narration, so write narration for `Beat name`. `hottake pause` and `resume` leave time out entirely when you need to reset something, and are the way to take a screenshot or think without recording the wait.

## 4. Edit

Write an edit list (JSON) and run `hottake edit list.json`. Times are seconds of the original, or marker names with an optional offset like `"Open Studio+1.5"`. Retakes are cut automatically (set `"autoRetakes": false` to do it by hand).

```json
{
  "cuts": [
    {"from": "Waiting: report", "to": "Done: report"}
  ],
  "autoZoom": true,
  "maxZoomsPerMinute": 4,
  "clickRings": true,
  "zooms": [{"at": "Export", "duration": 3, "scale": 2}],
  "texts": [{"text": "Export in one click", "at": "Export+0.5", "duration": 3, "position": "top"}],
  "shapes": [{"kind": "arrow", "at": "Share", "x1": 0.3, "y1": 0.7, "x2": 0.5, "y2": 0.5}],
  "narration": {"Intro": "This is…", "Export": "To share it…"},
  "narrationCaptions": true,
  "captionStyle": "classic",
  "captionPosition": "bottom"
}
```

- Cut waiting, retakes and dead air. Leave about half a second either side of a cut so it does not feel abrupt. A cut that removes a whole marker's stretch drops that beat from the narration script.
- Zoom only on the thing the sentence is about, for about 2–4 seconds. A zoom without `x` and `y` looks at the nearest click. More than one zoom every ten seconds feels busy: `autoZoom` adds one per group of clicks (dozens in a long demo), so pair it with `maxZoomsPerMinute` or list your own zooms instead.
- Keep captions short. Put a caption where the viewer is not looking at the pointer.
- `narrationCaptions` turns the `narration` lines into captions drawn in the picture, plus a `.vtt` file and the saved copy's transcript, so a demo with no spoken audio can still be followed (and search, the summary and chapters have text to use). Each line fills the part of the video that begins at its marker, split by sentence. Write them as captions, not as speech: short, present tense, what the viewer is looking at. A line too long for its beat is flagged in the narration script and would flash by as a caption, so shorten it. Do not also add `texts` captions in the same place. Record with **no audio**; nothing is spoken or recognised. The captions are the agent's words, so they say what you intended, not what the screen shows: check them with `hottake frames` after rendering.
- `keep` trims everything outside one stretch; `replace: true` starts over from the original if the take already has edits.
- Read the `warnings` in the reply (a marker name with no match, something that fell inside a cut) and fix the list.

The edit lands in the take's Studio draft, so the person can open the take in the Studio, look it over and change it. Hot Take refuses to overwrite edits that are already there unless you send `replace`, and refuses while the Studio has that take open.

## 5. Save and hand off

1. `hottake render` saves a new copy in the library (the original is never changed). Markers become chapters (a retake's failed attempt is not one).
   Then look at it: `hottake frames --scan` takes a picture from the middle of each chapter of that copy, lays them out on one contact sheet (its path is printed; open the image), and looks for text that looks sensitive in them. Check that captions, zooms and framing are as intended, and blur or re-record anything it flags. It only checks those moments, so it narrows what the person must watch; it does not replace it. `--at 12,40.5` picks moments yourself.
2. The edit step wrote `<take name>.narration.md` beside the video: each beat's time range on the **edited** video, your narration line, and a note when a line is too long for its beat. Fix long lines (shorten the line, or lengthen the beat by cutting less) and re-run `edit` with `replace: true` and `render` again.
3. Tell the person: where the video and narration script are, the final length, what you cut, and anything you could not verify. They record or generate the voice-over; Hot Take's Studio can add it as a voiceover track.

## Cleaning up

Your own test and failed takes stay in the person's library until removed. When you are done, `hottake discard --take NAME` moves one you recorded (or a copy you saved) to the Trash. It refuses takes the person recorded and never deletes anything permanently. Name the take you discard; do not guess, and tell the person what you removed.

## Rules

- Never turn on local agent control, change Settings, or start recording without the person having asked for a recording.
- Never leave a recording running: always `hottake stop` (an agent's take is stopped for you after 30 minutes).
- Do not claim the video looks good. You have not watched it; `hottake frames` shows still moments, not motion. Say what you did, what the pictures showed, and ask the person to watch it through, especially for sensitive text on screen.
- Do not use `click`, `key` or `type` for anything but driving the demo. They act as the person.
- Do not record a display you have not checked with `preflight`.

---
name: demo-recording
description: Plan, record and edit a screen demo of an app with Hot Take on this Mac, driving the app yourself. Use when asked to record a demo, walkthrough or product video; produces a tightened video with zooms and captions plus a voice-over script. Needs Hot Take's "Let local agents control recording" setting turned on.
---

# Record a demo with Hot Take

You drive the app being demoed (computer use, Playwright, AppleScript, whatever you have). Hot Take only records and edits, through the `hottake` command or its MCP tools (`hottake mcp`). Nothing leaves this Mac.

Before anything: run `hottake status`. If it says it cannot reach Hot Take, ask the person to open Hot Take and turn on **Settings ▸ Recording ▸ Let local agents control recording**. Do not try to turn it on yourself.

## 1. Propose, then wait

Write a short plan and show it to the person before recording:

- **Audience and length** (default: someone new to the app, 60–90 seconds).
- **Beats**: 4–8 steps. Each has a short **name** (it becomes a marker and a chapter), what you will click or type, and the one thing the viewer should notice.
- **Setup**: what must already be on screen or logged in, and any private data that must not appear (names, emails, keys). If something sensitive is unavoidable, plan a `blur` mark.
- **Narration**: one or two plain sentences per beat, written to be read aloud at about 2.5 words a second.

Wait for a yes or changes. Do not record before that.

## 2. Rehearse without recording

Walk the beats once with no recording. Fix anything that fails, pops up unexpectedly (notifications, update prompts, cookie banners) or is slow. Put the app back in its starting state.

## 3. Record

1. `hottake start` (add `--display N` for another screen). It returns once recording has really begun, after the countdown. The recording bar stays on screen.
2. For each beat, run `hottake marker "Beat name"` just before the first action, then do it. Move the pointer deliberately and click on the thing you mean: Hot Take notes clicks, and zooms aim at them.
3. When the app is slow (loading, installing, waiting for a response), mark it: `hottake marker "Waiting: report"` before and `hottake marker "Done: report"` after. These are what you cut.
4. `hottake stop`. It saves the take and prints its file, length and markers.

If a step goes wrong, do not stop. Mark `Retake: Beat name`, redo the step, and cut the failed attempt afterwards. `hottake pause` and `resume` leave time out entirely when you need to reset something.

## 4. Edit

Write an edit list (JSON) and run `hottake edit list.json`. Times are seconds of the original, or marker names with an optional offset like `"Open Studio+1.5"`.

```json
{
  "cuts": [
    {"from": "Waiting: report", "to": "Done: report"},
    {"from": "Retake: Export", "to": "Export"}
  ],
  "autoZoom": true,
  "clickRings": true,
  "zooms": [{"at": "Export", "duration": 3, "scale": 2}],
  "texts": [{"text": "Export in one click", "at": "Export+0.5", "duration": 3, "position": "top"}],
  "shapes": [{"kind": "arrow", "at": "Share", "x1": 0.3, "y1": 0.7, "x2": 0.5, "y2": 0.5}],
  "narration": {"Intro": "This is…", "Export": "To share it…"}
}
```

- Cut waiting, retakes and dead air. Leave about half a second either side of a cut so it does not feel abrupt. A cut that removes a whole marker's stretch drops that beat from the narration script.
- Zoom only on the thing the sentence is about, for about 2–4 seconds. A zoom without `x` and `y` looks at the nearest click. More than one zoom every ten seconds feels busy.
- Keep captions short. Put a caption where the viewer is not looking at the pointer.
- `keep` trims everything outside one stretch; `replace: true` starts over from the original if the take already has edits.
- Read the `warnings` in the reply (a marker name with no match, something that fell inside a cut) and fix the list.

The edit lands in the take's Studio draft, so the person can open the take in the Studio, look it over and change it. Hot Take refuses to overwrite edits that are already there unless you send `replace`, and refuses while the Studio has that take open.

## 5. Save and hand off

1. `hottake render` saves a new copy in the library (the original is never changed). Markers become chapters.
2. The edit step wrote `<take name>.narration.md` beside the video: each beat's time range on the **edited** video, your narration line, and a note when a line is too long for its beat. Fix long lines (shorten the line, or lengthen the beat by cutting less) and re-run `edit` with `replace: true` and `render` again.
3. Tell the person: where the video and narration script are, the final length, what you cut, and anything you could not verify. They record or generate the voice-over; Hot Take's Studio can add it as a voiceover track.

## Rules

- Never turn on local agent control, change Settings, or start recording without the person having asked for a recording.
- Never leave a recording running: always `hottake stop` (an agent's take is stopped for you after 30 minutes).
- Do not claim the video looks good. You have not watched it. Say what you did and ask the person to watch it through, especially for sensitive text on screen.

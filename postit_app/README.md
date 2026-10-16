# PostIt

A tiny native macOS post-it note that lives in the menu bar (no Dock icon). One borderless, resizable, colored note window that can float over every app, including full-screen apps, on all Spaces. Notes are markdown, rendered when you are not editing.

## Features

- Menu-bar item (`note.text`): Show/Hide Note, New Note, Pin on Top, Launch at Login, Quit.
- Pinned notes float on top of everything on every Space; unpinned notes behave like a normal window. No Accessibility permission needed.
- Several notes in one window: previous/next, new, delete (moved to the Trash), per-note color with a reset to classic yellow. Text switches between black and white to stay readable.
- A hover bar with these controls appears only while the mouse is over the note.
- View mode renders GitHub-flavored markdown (headings, lists, task lists, tables, code, quotes, links, images, strikethrough). Task-list checkboxes are clickable and write back to the file. Links open in your browser.
- Edit mode is a plain text editor. Every edit is saved immediately (atomic write).
- Window position and size are remembered. Drag a note anywhere in view mode; in edit mode drag the thin strip along the top.

## Build

```sh
./build.sh          # swift build -c release, assembles and ad-hoc signs PostIt.app
open PostIt.app
swift test          # tests for the task-toggle logic
```

Copy `PostIt.app` to `/Applications` if you want Launch at Login to work (macOS usually refuses it elsewhere; the app shows the error).

The app is only ad-hoc signed, so the first launch of a copy downloaded or moved around may be blocked: right-click the app and choose Open.

## Notes storage

One markdown file per note in `~/Library/Application Support/PostIt/`, named by timestamp (`20261016-153012-123.md`); the order of notes is the filename order. Colors and settings are in UserDefaults (`local.postit.app`). Relative image paths in a note resolve against that folder.

## Shortcuts

| Action | Keys |
|--------|------|
| Edit a note | double-click it, or Cmd+E |
| Back to view mode | Esc, Cmd+E, or click outside the note |
| Quit | Cmd+Q |

## Third-party

[marked](https://github.com/markedjs/marked) 15.0.12 (MIT licensed, license header kept in `Resources/marked.min.js`) renders the markdown, bundled so the app works offline.

## Limitations

Raw HTML in a note is rendered as-is, so only put markdown you trust in it.

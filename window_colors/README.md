# Window Colors

A VS Code extension that gives every window its own color, like [Peacock](https://github.com/johnpapa/vscode-peacock)
does, **including windows with no folder or workspace open**, which Peacock can't color.

## What you see

- The window border, title bar, activity bar and status bar in the window's color, with black or white text,
  whichever reads better. The border shows where VS Code draws its own title bar (the default on Windows and Linux).
- A **●** with the folder name (or "No folder") at the left of the status bar, in the status bar's text color (white,
  or black on light colors such as yellow); in the window's color when the bars aren't tinted. Click it to pick
  another color.
- A colored stripe down the left edge of every editor, with the same color along the scrollbar
  (`windowColors.stripeWidth`, `0` turns it off).

Each new window takes a color no other open window is using. A folder always starts with the same color, and a color
you pick is remembered for that folder (or that empty window) across reloads.

## Where the colors are written

VS Code takes border, title bar, activity bar and status bar colors only from the `workbench.colorCustomizations`
setting, and settings exist at two levels: user (every window) and workspace (one folder or `.code-workspace`).

- **Windows with a folder:** the colors go into the folder's `.vscode/settings.json`, as Peacock does
  (`windowColors.tintFolderWindows`).
- **Windows without a folder:** they have no workspace settings, so whenever one gets focus its colors go into your
  user settings (`windowColors.tintEmptyWindows`). Folder windows keep their own colors, because workspace settings
  win. With several empty windows open, the one you're in is always right, but the others show the color of the
  empty window focused last; the editor stripe still shows each window's own color.

The keys written include every one Peacock writes by default, so a folder that still has Peacock colors gets this
window's color everywhere. If Peacock is installed too, the two overwrite each other's colors; you get a one-time
warning to disable Peacock.

Your other `workbench.colorCustomizations` entries are kept, and turning a setting off removes only this extension's
entries.

## Install

Download `window-colors-0.2.2.vsix` (the `window-colors-vsix` artifact of the
latest [window_colors workflow run](https://github.com/alexlol87/public_ish_projects/actions/workflows/window-colors.yml)),
then either run

```sh
code --install-extension window-colors-0.2.2.vsix
```

or in VS Code: Extensions view → `…` menu → **Install from VSIX…**. Reload open windows to color them.

To build it yourself: `cd window_colors && npm ci && npx vsce package`.

## Settings

| Setting | Default | |
|---|---|---|
| `windowColors.stripeWidth` | `4` | Editor stripe width in pixels; `0` turns it off |
| `windowColors.tintFolderWindows` | `true` | Color the border and title/activity/status bars of folder windows (writes `.vscode/settings.json`, replacing colors left there by Peacock) |
| `windowColors.tintEmptyWindows` | `true` | Color the border and bars of windows without a folder while they have focus (writes your user settings) |
| `windowColors.palette` | built-in 10 | Colors handed out to new windows, `#rrggbb` |

Command: **Window Colors: Change This Window's Color**.

## How it works

- `lib/colors.js`: palette, color choice, readable text color, the colorCustomizations keys (pure functions).
- `lib/registry.js`: every window runs its own extension host process, so each window records `{id, pid, color}` in
  one small JSON file in the extension's global storage; entries of processes that no longer run are closed windows.
  It is only read and written when a window opens, closes or changes color, so nothing runs in the background.
- `extension.js`: the bar colors, the status bar item and the editor stripe.

Runs on the UI side (`extensionKind: ui`), so it also works in Remote SSH / WSL / container windows.

## Tests

`npm test` runs the unit tests (`node --test`). `npm run test:vscode` starts a real VS Code (an empty window, then a
folder window) and checks the extension in it; CI runs it with `xvfb-run` on VS Code 1.75 and current stable, see
`.github/workflows/window-colors.yml`.

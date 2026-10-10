# Window Borders

A macOS menu bar app that draws a colored border around every application window, with **a different color per
window**, even when several windows belong to the same app. Five VS Code windows might be green, red, blue, purple and
orange, so you can tell them apart at a glance (Terminal and VS Code were the priority, but every regular app's
standard windows get one).

- The border is a separate, transparent, click-through window placed directly above its target in the window stack.
  It never takes clicks or focus, and windows in front of a window also cover its border.
- A new window gets the palette color the fewest visible windows use, and keeps it for its whole lifetime. Optionally
  it gets the same color back after an app restart (matched by app + window title).
- Swift + AppKit (SwiftUI only for the settings window), macOS 14+, Apple Silicon. No third-party dependencies.
- Event-driven: Accessibility notifications plus one cheap window-server query every 2 s for what notifications miss.

## Download and install

1. Download `WindowBorders.zip` from the
   [latest release](https://github.com/alexlol87/public_ish_projects/releases/tag/window-borders-latest). Every change to
   `main` that passes CI replaces it with a fresh build.
2. Unzip it and move `Window Borders.app` to `/Applications`.
3. The app is ad-hoc signed (no paid Apple developer certificate), so macOS quarantines the download. Clear that once:
   ```sh
   xattr -dr com.apple.quarantine "/Applications/Window Borders.app"
   ```
   Or right-click the app → Open, then confirm under System Settings → Privacy & Security.
4. Open it and grant Accessibility when the onboarding window asks (see [Permissions](#permissions)).

When you install a newer build, remove the old Window Borders entry under Privacy & Security → Accessibility with
"−" and add the new one: each ad-hoc signed build counts as a new app.

## Build and run

You need Xcode 15.4 or later (Xcode 16 recommended) on macOS 14+.

```sh
cd window_borders
scripts/build-app.sh                 # -> build/Window Borders.app (release, arm64, ad-hoc signed)
open "build/Window Borders.app"
```

To install it, copy `Window Borders.app` to `/Applications`. Launch at login only works from the `.app` bundle,
ideally in /Applications.

Other ways to build:

```sh
swift build                          # debug build of the executable
swift test                           # BorderCore unit tests
xcodebuild build -scheme WindowBorders -destination 'platform=macOS,arch=arm64'
xcodebuild test  -scheme WindowBorders -destination 'platform=macOS,arch=arm64'
open Package.swift                   # opens the package in Xcode
```

`swift run` / the bare binary also works, but macOS then grants Accessibility to the program that launched it (for
example Terminal) rather than to Window Borders. Use the `.app` for real use.

**Signing:** `build-app.sh` signs ad hoc unless `SIGN_IDENTITY` is set, e.g.
`SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" scripts/build-app.sh`. With ad-hoc signing every rebuild
looks like a new app to macOS. After rebuilding, remove the old Window Borders entry in System Settings → Privacy &
Security → Accessibility (the "−" button) and grant it again. A real signing identity keeps the grant across rebuilds.

**CI:** `.github/workflows/window-borders.yml` runs on a macOS (Apple Silicon) runner for every push that touches this
folder:

- the unit tests;
- an `xcodebuild` build that fails on any compiler warning;
- the `.app` bundle, with a launch test.

The zipped `.app` is attached to each run as an artifact. On `main`, a second job then replaces the
`window-borders-latest` release with that build, so it can be downloaded without a GitHub login.

**App icon:** `Resources/AppIcon.svg` is the source: a screen with overlapping windows, each with its own colored
border. `Resources/AppIcon.png` is its 1024 px rendering, and `build-app.sh` turns the PNG into `AppIcon.icns` with
`sips` and `iconutil`. After editing the SVG, re-render the PNG with any SVG renderer, e.g.
`rsvg-convert -w 1024 -h 1024 Resources/AppIcon.svg -o Resources/AppIcon.png`.

## Permissions

| Permission | Needed? | Why |
|---|---|---|
| **Accessibility** | Yes | It is how the app finds other apps' windows, reads their position, size, title, minimized and fullscreen state, and gets notified when they open, close, move, resize, minimize or change focus. |
| Screen Recording | No | Window titles come from Accessibility. CGWindowList is used only for window IDs, owner PIDs, bounds and layers, which need no permission. The app never asks for it. |
| Input Monitoring | No | The ⌃⌥⌘B hot key uses Carbon `RegisterEventHotKey`, which needs no permission. The mouse-button monitor used while dragging also needs no extra permission. |

On first launch, if Accessibility isn't granted, an onboarding window explains why it's needed. Its **Open System
Settings** button opens Privacy & Security → Accessibility. The app polls for the grant once a second only while that
window is open, then starts drawing borders. Nothing is recorded, stored (except your settings and remembered colors
in UserDefaults) or sent anywhere.

**Not sandboxed.** The App Sandbox doesn't allow the Accessibility API on other apps' windows, so the app is
deliberately not sandboxed and can't ship on the Mac App Store. It runs with the hardened runtime and needs no
entitlements.

## Using it

The menu bar icon (a dashed square, dimmed while borders are off) has these items:

- **Enabled**: turn every border on or off.
- **Focused window**: the app, title and color of the window you were using.
- **Recolor Focused Window** (⌃⌥⌘B from anywhere): move it to the next palette color.
- **Set Focused Window Color**: pick a specific palette color.
- **Pin \<App\> to This Color / Unpin**: every window of that app uses one color. While an app is pinned, recoloring
  changes the pin.
- **Settings…**, **Launch at Login**, **Grant Accessibility Access…** (shown when missing), **Quit**.

Settings (saved in UserDefaults):

- **General**:
  - the on/off switch;
  - border width (default 4 pt);
  - corner radius (auto, or a custom value);
  - active-window emphasis: the focused window gets a thicker border, others get reduced opacity;
  - borders on fullscreen windows (off by default);
  - borders in Mission Control and App Exposé (on by default, see below);
  - border layering: attached (default) or floating fallback;
  - remember colors across restarts;
  - the hot key;
  - launch at login (SMAppService).
- **Palette**: add, remove, reorder and edit colors. The default palette is green, red, blue, purple, orange, yellow,
  cyan, pink, teal and brown.
- **Apps**:
  - which apps get borders: all apps (default), only the selected apps, or all except the selected apps;
  - per-app color pins.

## How color assignment works

- **New window**: gets the palette color used by the fewest *visible* bordered windows. Ties go to palette order, so
  the first windows get green, red, blue, and so on. With more windows than colors, colors repeat as evenly as
  possible.
- **When colors are picked**: a window gets its color when its border first appears, not when the window is
  created, so a burst of new windows (VS Code restoring several workspaces) still gets distinct colors.
- **Palette edits**: editing a palette color in place recolors the windows wearing it. Adding, removing or
  reordering colors leaves existing windows alone.
- **Lifetime**: a window's color never changes on its own. It only changes when you recolor it, pin its app, or within
  the first 5 s if its remembered color is found (see below).
- **Remember colors** (best effort, can be turned off): colors are remembered per app bundle ID plus a *normalized*
  window title.
  - **What normalization strips**: dirty markers ("●"), terminal sizes ("80×24") and app-name suffixes.
  - **VS Code family** (VS Code, Insiders, VSCodium, Cursor): only the workspace name is kept, so a window keeps its
    color whichever file is open.
  - **Shared titles**: several windows can share a title (two Terminal windows called "alex — -zsh"). Each such title
    remembers its last 10 colors. A remembered color is never given to a window while another window of the same
    app wears it.
  - **Late titles**: apps often set the title shortly after opening a window. If a remembered color turns up within
    5 s and the window still has its first, automatically picked color, it switches once to the remembered color.

## Architecture

```
Sources/BorderCore/           Pure logic, Foundation/CoreGraphics only, unit tested
  ColorPicker, ColorAssigner    least-used selection, lifetime-stable assignment, manual cycle/set
  ColorMemory                   title normalization + remembered colors (bundle ID + title)
  CoordinateConverter           AX/CG (top-left origin) <-> AppKit (bottom-left origin)
  BorderGeometry                overlay frame, stroke rect, concentric corner radius, pixel alignment
  AppFilter, WindowEligibility, RGBAColor, Palette
Sources/WindowBorders/        The AppKit app
  Tracking/WindowTracker        AX enumeration + AXObservers per app, NSWorkspace launch/quit/activate/hide/Space
                                notifications, 2 s reconcile pass; emits add/update/remove/focus events
  Tracking/AppObserver          one AXObserver per app, routing C callbacks back to the tracker
  Tracking/AXAccess, WindowServer   typed AX attribute reads, CGWindowList helpers
  Tracking/MissionControlObserver   when Mission Control opens/closes: Dock notifications, sentinel window, Dock tree
  Tracking/MissionControlSentinel, MissionControlTree   the transient sentinel window; the Dock's "mc" group lookup
  Overlay/BorderOverlayController   one BorderWindow per tracked window: visibility rules, layout, z-order
  Overlay/BorderWindow, BorderView  borderless click-through NSWindow + CAShapeLayer stroke
  Overlay/ColorService          ColorAssigner + ColorMemory + per-app pins, persistence
  Overlay/DragFollower          per-frame border following while the mouse button is held
  Overlay/MissionControlBorders     thumbnail borders on one stationary canvas per display while Mission Control is open
  Settings/SettingsStore        @Published settings persisted to UserDefaults; SwiftUI settings views
  MenuBar/MenuBarController     status item and menu
  Onboarding/, System/          Accessibility onboarding, ⌃⌥⌘B hot key, SMAppService login item
  App/                          main.swift + AppDelegate/AppCoordinator (composition root)
Tests/BorderCoreTests/        ColorAssigner, ColorMemory, coordinate conversion, geometry, filters, colors
```

### Data flow

1. `WindowTracker` keeps a `TrackedWindow` per standard window, with:
   - its CGWindowID, from `_AXUIElementGetWindow`;
   - frame, title, minimized, fullscreen, app-hidden, on-screen and focused state.
2. The tracker tells `BorderOverlayController` about every change.
3. The controller converts the frame to AppKit coordinates and computes the border layout.
4. It asks `ColorService` for the window's color and shows, moves or hides that window's border.

### Coordinates and multiple displays

AX and CGWindowList use global coordinates with the origin at the top-left of the primary display and y growing
down; AppKit uses the bottom-left of the primary display with y growing up. The conversion is
`appKitY = primaryScreenHeight − axY − height`, where the primary screen is `NSScreen.screens[0]`.

- **Arrangements**: both coordinate spaces are in points across all displays, so the conversion holds for any
  arrangement (displays left, above or below, negative coordinates). The tests cover these cases.
- **Scale factors**: each border's line width is rounded to whole pixels using the scale of the display it overlaps
  most.
- **Display changes**: when displays change (plugging in a display, a resolution change), every border is laid out
  again.

### Performance

- **Almost no polling at idle**: everything is driven by notifications, plus two cheap checks.
  - The 2 s (±1 s tolerance) reconcile pass makes one CGWindowList call and returns at once when nothing changed.
  - A once-a-second (±0.5 s) Accessibility call to the Dock is the safety net for Mission Control, whose
    notifications don't arrive on every Mac; normally a sentinel window notices it first (see below).
- **Moves and resizes**: they redraw only that window's border, inside a `CATransaction` with animations disabled, so
  nothing animates or flickers.
- **While a mouse button is held**:
  - A display link samples the focused window's bounds from the window server each frame and moves its border, so
    drags and live resizes track smoothly even in apps that only post their AX moved/resized notification at the end.
  - The link stops on mouse-up, so it costs nothing at idle. The window is sampled twice more (0.4 s and 1.2 s
    later) so the border catches up with snapping or animations that finish after the button is released.
  - It is suspended while Mission Control is open, where the window server reports thumbnail bounds. Without that,
    clicking a thumbnail left the border on the thumbnail's rect after Mission Control closed.
- **Mission Control**: nothing but the sentinel's notifications and the once-a-second Dock check runs outside it.
  Inside it, the Dock is checked 2.5 times a second (10 times a second for a moment after a click or other sign of
  the exit), the thumbnails are sampled with one window-server call at the same rates, and a sample that found
  nothing new touches no layer. The apps are asked which windows are on the current Space when Mission Control
  opens, after a Space switch and otherwise at most every 2 s, with a 0.1 s timeout per app, so a slow app cannot
  stall the thumbnail borders for long.
- **Many windows**: each border is a small layer-backed window. Updates skip unchanged state, so 50+ windows are fine.

## Mission Control and App Exposé

With **Settings → General → Show borders in Mission Control** (on by default), each window's border is drawn around
its thumbnail in Mission Control (three-finger swipe up) and App Exposé (swipe down), in the window's own color, so
you can pick a window out of dozens by color.

- **Detection**: macOS has no public API for Mission Control, so three sources are combined, each checked against
  the Dock's Accessibility tree: the Dock publishes a Mission Control group (`mc`) in it only while Mission Control
  is open.
  - The app registers for the Dock's private Accessibility notifications (`AXExposeShowAllWindows`,
    `AXExposeExit`, ...), the approach yabai uses. On at least one current Mac they register fine but never arrive.
  - A *sentinel*: a 2×2 pt transparent window of the same transient kind as the borders, kept under the middle of
    the menu bar where nothing covers it. Mission Control hides transient windows and shows them again when it
    closes, so the sentinel's occlusion state flips at both moments (`NSWindow.didChangeOcclusionStateNotification`,
    no polling). A flip to hidden is confirmed by looking for the Dock's group, a few times over the next second
    since the Dock builds it a moment after Mission Control starts; a flip to visible is a sign of the exit.
  - As the safety net, the Dock's tree is checked once a second while Mission Control is closed. Borders therefore
    appear as soon as the Dock publishes the group when the sentinel works, and within about a second otherwise.
  - **Leaving**: while Mission Control is open the Dock's group is checked 2.5 times a second, and three checks in
    a row without it end the mode (it was once seen missing for a single check while Mission Control stayed open).
    Signs of the exit make this faster: a mouse click (the user picking a window or clicking away), the sentinel
    reappearing, and the window server no longer reporting thumbnail bounds (the windows zooming back to full
    size). Each switches to 10 checks a second for a moment; a click needs two misses in a row, the other two one.
    Picking a window therefore ends the mode within about 0.1–0.3 s of the Dock dropping the group, instead of
    0.8–1.2 s. The exit detection does not depend on the thumbnail borders being enabled.
- **Placement**: while Mission Control is open, the window server reports each window's thumbnail bounds, while
  Accessibility keeps the real frame. Bounds uniformly scaled down from the real frame are a thumbnail (confirmed on
  a real Mac). Its border is scaled with it, including the corner radius, with a 2 pt minimum width. The Dock's own
  tree carries no usable thumbnail frames.
- **Only the Space you're on**: during Mission Control the window server also reports thumbnail bounds for windows
  of other Spaces, including full-screen apps, which Mission Control doesn't show on the current Space.
  - Only windows the apps themselves list on the active Space get a thumbnail border (Accessibility lists an app's
    windows on the active Space only).
  - That list is asked when Mission Control opens, again after a Space switch (so swiping between Spaces inside
    Mission Control follows along) or a new window, and otherwise at most every 2 s. Apps with no window on screen
    are not asked, the others answer within 0.1 s or keep their last known state.
- **Drawing**: the thumbnail borders are drawn on one transparent, click-through canvas per display.
  - The canvases are stationary, so Mission Control leaves them in place instead of laying them out with the other
    windows, and they sit above Mission Control.
  - They are ordered in at startup and parked at 1×1 pt, and only resized while Mission Control is open.
  - The normal borders are hidden by Mission Control as before.
- **Updates**: the borders are re-placed 10 times a second during the opening animation, then 2.5 times a second
  while Mission Control stays open. Outside Mission Control only the once-a-second check of the Dock runs.
- **Picking a window**: on the mouse click the thumbnail borders are cleared at once (borders sampled at the
  thumbnail positions would otherwise trail the window zooming back to full size) and drawn again half a second
  later if Mission Control turns out to be still open (a click on the Spaces bar, a thumbnail drag). Once the exit
  is confirmed the normal borders, which Mission Control shows again by itself, are re-stacked 0.5 s and 1.2 s
  later, after its exit animation.
- **Limits**:
  - Show Desktop, and windows App Exposé leaves at full size, get no thumbnail border.
  - Borders can lag briefly behind thumbnails that move or zoom.
  - Dragging a thumbnail (to another Space) hides the thumbnail borders for half a second, like a click.
  - The feature relies on the Dock's private Mission Control group and on how the window server reports
    thumbnail bounds. If a macOS update changes either, borders are simply hidden in Mission Control again.
- **Diagnostics**: if no borders show in Mission Control, run this in Terminal, open Mission Control once and close
  it. The log shows whether and how Mission Control was noticed (notification, sentinel or poll), which signs of the
  exit were seen (mouse, sentinel, no thumbnails) and when the Dock confirmed it, and how many thumbnail borders
  were drawn:

  ```sh
  log stream --level info --predicate 'subsystem == "com.codefactory.WindowBorders"'
  ```

## Known limitations and workarounds

- **Z-order**:
  - **Normal behavior**: each border is ordered directly above its own window
    (`NSWindow.order(.above, relativeTo: windowNumber)`). Windows in front of a window also cover its border.
  - **Re-raised windows**: when an app activates, or its focused window changes, macOS raises its windows above their
    borders, and the borders are re-ordered when the AX focus/activation notification arrives. During that short gap
    (usually a few ms) a border can briefly disappear behind its window.
  - **Missed raises**: an app that raises a background window without any focus or activation change (e.g. "Bring All
    to Front" in an already active app) leaves that border hidden until the next focus change.
  - **Fallback**: if attached ordering misbehaves for you, Settings → General → Border layering → *Above all windows*
    keeps every border above all normal windows, so borders never hide behind their own window.
    - To keep a covered window's border from drawing over the windows in front of it, each floating border is masked
      by the windows in front of its own, read from the window server's front-to-back list.
    - The mask is recomputed when a tracked window moves, resizes, opens, closes or changes focus. A panel or other
      untracked window that moves on its own updates the mask at the next such event.
    - Covering windows are treated as plain rectangles, so their rounded corners hide a few points of the border
      behind them.
- **Which windows get a border**: only AX windows with subrole `AXStandardWindow`, at least 60×40 pt, on window layer 0.
  - Menus, tooltips, popovers, sheets, panels, dialogs, the Dock, the menu bar and other system UI are ignored by
    design.
  - Apps that report their main windows with another subrole get no border: some Java, custom-drawn or game windows.
- **Corner radius**: macOS has no API for another window's corner radius.
  - **Auto** uses 10 pt on macOS 14/15 and 16 pt on macOS 26+, which fits standard titled windows.
  - **Custom** is the fix for apps whose corners differ.
- **Spaces**:
  - Borders join all Spaces, but each is shown only while its window is on an active Space (CGWindowList's on-screen
    list), so each border appears only on its window's Space.
  - Right after a Space switch a border can linger briefly until the tracker sees its window is off screen.
  - AX lists only windows on the active Space, so a window that was opened on another Space before Window Borders
    started is found when you switch to that Space.
- **Mission Control and App Exposé**: see the section below.
- **Fullscreen**:
  - Borders on fullscreen windows are hidden by default.
  - When enabled, the stroke is drawn inside the screen edge with square corners, since there is no room outside.
- **Stage Manager**: untested.
  - Off-stage thumbnails are not on screen to the window server, so they get no border.
  - The stage's own windows get normal borders.
  - With Stage Manager's animations, a border can lag a moment behind its window.
- **Window identity**:
  - **The private API**: an AX window is mapped to its window-server ID with the private
    `_AXUIElementGetWindow`, the only way to do it. yabai, Rectangle, AltTab and Hammerspoon have relied on it for
    years.
  - **When it fails**: the app falls back to matching same-process windows by exact bounds, which can confuse two
    windows stacked exactly on top of each other.
- **Slow or hung apps**: AX calls use a 0.5 s timeout, so a hung app can cause brief stalls while it's retried, with
  retries backing off up to 60 s.
- **Drag following**:
  - Only the focused window is followed per frame.
  - A background window moved by a window manager or script updates when its app posts its AX moved/resized
    notification, which some apps only do at the end.
- **Remembered colors**:
  - Restore is a best-effort heuristic.
  - Windows with empty titles aren't remembered.
  - Apps that put a document or page name in the title (browsers) only match when the title is identical.
  - Which of several same-titled windows gets which remembered color isn't guaranteed.
- **Native tabs** (Terminal, Finder, Safari): each tab is its own window, and only the selected tab is on screen. The
  border follows the selected tab, so each tab can show a different color.
- **No Dock icon**: the app has no Dock icon. Open Settings from the menu bar icon, or launch the app again from
  Finder/Spotlight while it runs.

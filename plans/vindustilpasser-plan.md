# vindustilpasser — Implementation Plan for Codex CLI

## 0. Purpose

Build a native macOS utility named **vindustilpasser** for resizing and positioning windows of other applications.

The application is a small menu-bar/agent-style utility, not a normal document application. Its primary interaction is a global hotkey that opens a translucent grid panel on the display containing the last active window of another application. The user selects a grid area with the mouse or keyboard; after confirmation, vindustilpasser resizes and repositions that external window.

The project must be buildable entirely from the command line using **Command Line Tools for Xcode**, without installing or using the full Xcode IDE.

This document is intended to be consumed by Codex CLI as the implementation specification. Implement the project incrementally, compile after each major phase, and keep the project runnable at every step.

---

# 1. Hard requirements

## 1.1 Platform and technology

Use:

- Swift
- AppKit
- Foundation
- ApplicationServices / Accessibility (`AXUIElement`)
- Carbon/HIToolbox only for global hotkeys (`RegisterEventHotKey`)
- Swift Package Manager
- programmatic UI only

Do not use:

- SwiftUI
- Xcode projects
- `.xcodeproj`
- `.xcworkspace`
- Storyboards
- XIB/NIB files
- Interface Builder
- third-party UI frameworks
- third-party hotkey libraries
- App Sandbox
- Mac App Store APIs/workflows
- Developer ID distribution requirements
- notarization

The app is for local use only.

Recommended minimum deployment target:

```text
macOS 13.0+
```

Keep the deployment target easy to change later.

---

## 1.2 Application behavior

The application must:

- have no Dock icon;
- have no normal application menu bar;
- normally run without any visible standard window;
- optionally show an icon in the macOS menu bar;
- register a configurable global activation hotkey;
- when activated, find the last active/focused window belonging to another application;
- show a translucent, borderless panel centered on the screen containing that target window;
- keep the target application/window logically selected even though the vindustilpasser panel receives keyboard/mouse input;
- show an interactive grid;
- default to an 8×8 grid;
- temporarily double grid resolution while Option is held;
- allow mouse selection of a rectangular grid area;
- allow keyboard movement and resizing of the selection;
- only resize/reposition the target window after confirmation;
- close the panel after applying a selection;
- close the panel without modifying the target on Escape;
- treat the activation hotkey as a panel toggle: if the panel is open, pressing the activation hotkey closes it without applying;
- support predefined window-area presets;
- support global preset shortcuts;
- support local preset shortcuts active only while the panel is open;
- provide a Settings window;
- provide an About window/panel from the menu-bar icon;
- support Cmd+, to open Settings while the panel is open;
- support Cmd+Q to quit while vindustilpasser UI is open;
- store settings in:

```text
$HOME/.config/vindustilpasser/settings.json
```

---

# 2. Accessibility and window control

## 2.1 Required mechanism

Use the macOS Accessibility API.

The core external-window API is:

```swift
AXUIElement
```

The application must check permission with:

```swift
AXIsProcessTrusted()
```

and may request the standard user prompt using:

```swift
AXIsProcessTrustedWithOptions(...)
```

with `kAXTrustedCheckOptionPrompt`.

Do not attempt to bypass TCC.

Do not:

- edit the TCC database;
- depend on `tccutil` to grant access;
- use root-only trust hacks;
- use `AXMakeProcessTrusted` as the normal application flow.

The user must explicitly grant Accessibility access in macOS System Settings.

No special App Sandbox entitlement is required because the application is intentionally not sandboxed.

---

## 2.2 Window lookup

When a command needs to operate on another application:

1. determine the external application PID;
2. create an AX application object:

```swift
let appElement = AXUIElementCreateApplication(pid)
```

3. read `kAXFocusedWindowAttribute`;
4. if no focused window is available, try `kAXMainWindowAttribute`;
5. validate that the result is an AX window;
6. reject vindustilpasser's own windows;
7. keep that `AXUIElement` as the target for the complete panel interaction.

Do not re-query the focused window after opening the panel.

The panel may receive keyboard focus, so the target window must be captured before showing the panel.

---

## 2.3 Last external application tracking

Because Settings, About, or a status-menu interaction can temporarily make vindustilpasser the active application, track the most recently active non-vindustilpasser application.

Use:

```swift
NSWorkspace.shared.notificationCenter
```

and observe application activation notifications.

Maintain something similar to:

```swift
struct LastExternalApplication {
    let pid: pid_t
    let bundleIdentifier: String?
}
```

Rules:

- whenever a non-vindustilpasser app becomes active, update the stored PID;
- when the activation hotkey is pressed and the current frontmost app is external, use it;
- when vindustilpasser itself is frontmost, use the last external app if it still exists;
- resolve its focused/main window at command time;
- never resize vindustilpasser's Settings/About/Grid windows through the external-window manager.

This also makes activation from the menu-bar icon behave correctly.

---

## 2.4 Target object

Create a value/reference type such as:

```swift
final class WindowTarget {
    let pid: pid_t
    let application: NSRunningApplication
    let axWindow: AXUIElement
    let originalAXFrame: CGRect
    let screen: NSScreen
}
```

This object exists for one operation/session.

Before applying a frame, verify the AX object is still valid. The user may close the target window while the grid is open.

---

## 2.5 Read/write AX attributes

Implement small typed wrappers around `AXUIElementCopyAttributeValue` and `AXUIElementSetAttributeValue`.

Required attributes:

```text
kAXPositionAttribute
kAXSizeAttribute
kAXFocusedWindowAttribute
kAXMainWindowAttribute
kAXFullScreenAttribute
kAXMinimizedAttribute
```

Before resizing, use:

```swift
AXUIElementIsAttributeSettable(...)
```

for position and size.

Use `AXValueCreate` with:

```text
kAXValueCGPointType
kAXValueCGSizeType
```

when writing geometry.

Centralize all raw Core Foundation / `AnyObject` casting inside the Accessibility module. The rest of the app should work with Swift types.

---

## 2.6 Unsupported windows

Treat these as normal errors, not crashes:

- no focused/main window;
- target window closed;
- target application quit;
- position is not settable;
- size is not settable;
- minimized window if the operation cannot be applied safely;
- native macOS fullscreen window;
- Accessibility permission missing;
- transient AX failures;
- application-enforced minimum/maximum sizes.

Use a clear error enum, for example:

```swift
enum WindowOperationError: Error {
    case accessibilityDenied
    case applicationUnavailable
    case noWindow
    case targetGone
    case minimized
    case nativeFullScreen
    case positionNotSettable
    case sizeNotSettable
    case axError(AXError)
}
```

Do not automatically exit native fullscreen mode.

A "Full" preset means filling `NSScreen.visibleFrame`, not entering macOS native fullscreen.

---

# 3. Coordinate systems

This is a critical module and must be implemented and tested separately.

## 3.1 Coordinate spaces

The project deals with:

1. AppKit screen coordinates;
2. Accessibility/Quartz-style global screen coordinates;
3. grid coordinates;
4. local `NSView` coordinates.

Do not scatter coordinate conversion code across controllers.

Create:

```text
Geometry/
    ScreenGeometry.swift
    GridGeometry.swift
```

All AX/AppKit conversion must go through `ScreenGeometry`.

---

## 3.2 Primary display

Determine the primary display robustly using `CGMainDisplayID()`.

Map `NSScreen` instances to display IDs through:

```swift
NSScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
```

Do not assume `NSScreen.main` is always the physical primary display; `NSScreen.main` changes with key-window state.

---

## 3.3 AX/AppKit frame conversion

Implement and unit-test conversion functions such as:

```swift
func appKitRect(fromAX rect: CGRect) -> CGRect
func axRect(fromAppKit rect: CGRect) -> CGRect
```

The primary-screen height is the reference for converting the vertical axis.

The implementation must support:

- monitor to the left of the main monitor;
- monitor to the right;
- monitor above;
- monitor below;
- negative coordinates;
- different display sizes;
- Retina and non-Retina combinations.

Do all normal window calculations in logical screen points. Do not mix backing pixels into window geometry.

---

## 3.4 Determine target screen

Given the target window frame:

1. convert the AX frame to AppKit coordinates;
2. intersect the window rect with every `NSScreen.frame`;
3. calculate intersection area;
4. choose the screen with the largest intersection area;
5. if there is no meaningful intersection, fall back to the screen containing the window center;
6. if that still fails, fall back to the primary screen.

This is better than using the window center alone for windows spanning multiple monitors.

---

# 4. Grid geometry model

## 4.1 Base grid

Default:

```text
columns = 8
rows = 8
```

Allow the user to configure columns and rows in Settings.

Recommended validation:

```text
1...32 columns
1...32 rows
```

The visual grid gap must never affect actual window geometry.

---

## 4.2 Fine grid with Option

Holding Option doubles resolution.

Examples:

```text
8×8  -> 16×16
6×8  -> 12×16
10×10 -> 20×20
```

Do not rewrite persistent settings when Option is pressed.

Recommended internal model:

- internally keep panel selection in a fine lattice of `baseGrid * 2`;
- when Option is not held, snapping step is 2 fine-grid units;
- when Option is held, snapping step is 1 fine-grid unit.

This avoids selection drift when Option is pressed/released.

Example for an 8×8 base grid:

```text
internal grid = 16×16

normal mode:
0, 2, 4, 6, ...

Option mode:
0, 1, 2, 3, ...
```

---

## 4.3 Grid selection

Use a top-left-origin grid model because that matches the visual interaction.

Example:

```swift
struct GridSelection: Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
}
```

All fields are integral fine-grid units while the panel is open.

Selection must always satisfy:

```text
x >= 0
y >= 0
width >= minimum step
height >= minimum step
x + width <= effectiveFineColumns
y + height <= effectiveFineRows
```

---

## 4.4 Mapping grid area to a screen

Window placement uses:

```swift
screen.visibleFrame
```

not:

```swift
screen.frame
```

This avoids covering the menu bar and Dock.

Use shared boundary calculations so adjacent selections share exactly the same edge.

For top-left grid coordinates:

```text
left   = visible.minX + visible.width  * x / columns
right  = visible.minX + visible.width  * (x + width) / columns
top    = visible.maxY - visible.height * y / rows
bottom = visible.maxY - visible.height * (y + height) / rows
```

Then:

```text
rect.x      = left
rect.y      = bottom
rect.width  = right - left
rect.height = top - bottom
```

Do not subtract visual cell gaps.

Do not create geometry by summing rounded cell widths repeatedly; derive both edges from the whole-screen fraction to avoid cumulative errors.

---

# 5. Preset area representation

Presets must remain stable even if the user later changes the default grid.

Store a preset area as its own rational grid definition:

```swift
struct StoredGridArea: Codable, Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
    var columns: Int
    var rows: Int
}
```

Example left half:

```json
{
  "x": 0,
  "y": 0,
  "width": 4,
  "height": 8,
  "columns": 8,
  "rows": 8
}
```

This means exactly one half even if the active editing grid later changes to 12×10.

Do not store only floating-point fractions as the canonical preset format.

---

# 6. Grid panel

## 6.1 Window class

Use a custom `NSPanel`.

Recommended style:

```swift
NSPanel(
    contentRect: ...,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
```

Subclass it:

```swift
final class GridPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

Also configure:

```text
isOpaque = false
backgroundColor = .clear
hasShadow = true
hidesOnDeactivate = false
level = .floating
```

Use suitable collection behavior such as:

```text
.moveToActiveSpace
.transient
.fullScreenAuxiliary
```

Do not make the panel a normal titled window.

---

## 6.2 Appearance

Build a modern HUD-style panel rather than reproducing the old Divvy design.

Suggested structure:

```text
┌────────────────────────────────┐
│ [app icon] Application Name    │
│                                │
│       interactive grid         │
│                                │
│ ⌥ fine grid   ⇧ resize   ↩     │
└────────────────────────────────┘
```

Use:

- `NSVisualEffectView`;
- system material appropriate for HUD/window surfaces;
- system Light/Dark appearance;
- rounded corners;
- shadow;
- system accent color for selection;
- no hard-coded imitation of Divvy colors.

The panel should visually communicate:

- target application name;
- target application icon;
- current grid selection;
- whether fine mode is active;
- optionally the current logical size, e.g. `4×8`.

---

## 6.3 Grid aspect ratio

The visual grid should roughly match the aspect ratio of the target screen's `visibleFrame`.

Do not force it to be square.

Use a reasonable fixed panel width, for example approximately 420 points, then derive grid height from display aspect ratio and clamp to a usable range.

The exact constants can be tuned after the first working build.

---

## 6.4 Drawing implementation

Use one custom:

```swift
final class GridView: NSView
```

Do not create one `NSView` per cell.

`GridView.draw(_:)` should draw:

- cell boundaries/background;
- small visual gaps between cells;
- current selection;
- hover/drag feedback.

Visual cell gaps are rendering only.

---

# 7. Panel activation flow

Implement this exact order:

```text
activation hotkey/status command
    ↓
check Accessibility permission
    ↓
resolve frontmost/last external app
    ↓
capture focused/main AX window
    ↓
read original frame
    ↓
determine target screen
    ↓
create WindowTarget
    ↓
initialize selection from target window frame
    ↓
show non-activating GridPanel on target screen
```

Never show the panel first and then ask AX which external window was focused.

---

## 7.1 Initial selection

When the panel opens:

1. read the target window frame;
2. map it into the target screen's `visibleFrame`;
3. quantize it to the normal base grid;
4. display that as the initial selection.

If the current frame cannot be mapped sensibly, default to the entire screen.

This gives keyboard control a meaningful starting selection.

Mouse-down may replace the initial selection immediately.

---

# 8. Mouse interaction

Implement:

```text
mouseDown
mouseDragged
mouseUp
```

## 8.1 Mouse down

On `mouseDown`:

- determine the grid cell under the pointer;
- set it as the drag anchor;
- begin a selection;
- do not modify the external window.

## 8.2 Mouse drag

On `mouseDragged`:

- snap using normal/fine mode;
- form a normalized rectangle from anchor to current cell;
- update highlight only;
- do not resize the external window.

## 8.3 Mouse up

On `mouseUp`:

1. validate selection;
2. map it to `screen.visibleFrame`;
3. convert to AX coordinates;
4. apply to the captured target;
5. close the panel.

The external window changes only after mouse release.

If the operation fails, close or retain the panel according to error severity; for recoverable window constraints, show a concise error and close.

---

# 9. Keyboard interaction

While the panel is open:

```text
Arrow              move selection
Shift + Arrow      resize selection
Option             temporarily enable fine grid
Enter / Return     apply and close
Escape             cancel and close
activation hotkey  cancel and close
Cmd+,               cancel panel and open Settings
Cmd+Q               quit vindustilpasser
local preset key    apply preset and close
```

---

## 9.1 Arrow movement

Without Shift:

```text
Left   -> x -= step
Right  -> x += step
Up     -> y -= step
Down   -> y += step
```

where:

```text
step = 2 fine units normally
step = 1 fine unit while Option is held
```

Clamp the whole selection inside the grid.

---

## 9.2 Shift resizing

Use a simple top-left-anchored rule:

```text
Shift+Left   -> decrease width by one step
Shift+Right  -> increase width by one step
Shift+Up     -> decrease height by one step
Shift+Down   -> increase height by one step
```

Keep x/y unchanged.

Clamp to:

- minimum one current snap unit;
- grid right/bottom boundary.

This gives both grow and shrink operations with four keys and is deterministic.

Document this behavior in the UI/help text.

---

## 9.3 Option state

Observe modifier changes while the panel is visible.

When Option changes:

- update `fineMode`;
- redraw grid;
- retain the same internal fine-grid selection;
- change only the snap step.

Do not resize the target until confirmation.

---

# 10. Applying a frame

Create one method such as:

```swift
func apply(_ rect: CGRect, to target: WindowTarget) throws
```

Suggested sequence:

1. verify Accessibility permission still exists;
2. verify target AX object is valid;
3. verify not native fullscreen;
4. verify position and size are settable;
5. create AX size value;
6. set size;
7. create AX position value;
8. set position;
9. read back actual size/position;
10. if the application adjusted origin after resizing, optionally set position once more;
11. return the actual final frame for diagnostics.

Some apps enforce window constraints. Do not assume requested frame equals final frame.

No custom window-resize animation is required for v1.

---

# 11. Global hotkeys

Use Carbon `RegisterEventHotKey`.

Do not use a global `CGEventTap` for normal shortcut handling.

Implement:

```text
HotKeys/
    HotKey.swift
    HotKeyManager.swift
    HotKeyRecorderView.swift
```

The manager should:

- install one Carbon hotkey event handler;
- register the activation hotkey;
- register all global preset hotkeys;
- map Carbon hotkey IDs to actions;
- unregister old hotkeys before destruction;
- update registrations when settings change.

All resulting app actions must be dispatched to the main thread / `@MainActor`.

---

## 11.1 Hotkey data model

Use a structured representation:

```swift
struct HotKey: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: HotKeyModifiers
    var displayKey: String?
}
```

Modifiers should support:

```text
Command
Option
Control
Shift
```

Do not store the canonical shortcut as a string such as `"cmd+F10"`.

A display string such as `⌘F10` is UI only.

---

## 11.2 Global shortcut validation

For global shortcuts:

- require at least one modifier, OR
- allow bare function keys such as F1...F20;
- reject plain printable keys such as `1`, `A`, `/` without modifiers.

This prevents the app from stealing normal typing globally.

Detect duplicate assignments.

The activation shortcut and global preset shortcuts must not collide.

When the user changes a global shortcut:

1. attempt to register the new shortcut;
2. if registration succeeds, unregister/replace the old shortcut;
3. persist settings;
4. if registration fails, keep the old shortcut and show a clear conflict message.

Do not persist a shortcut that is known to have failed registration.

---

# 12. Local preset shortcuts

Local preset shortcuts are not globally registered.

They are handled only by the GridPanel while it is visible.

Examples:

```text
1
2
3
Q
W
```

## 12.1 Keyboard-layout-independent matching

Local preset shortcuts must be bound to the **physical macOS virtual key code**, not to the character produced by the currently selected keyboard layout.

For example, if the user records the local shortcut:

```text
W
```

while using an English keyboard layout, the shortcut is stored using the virtual key code for the physical `W` key.

If the user later switches to the Ukrainian layout, pressing the same physical key produces:

```text
Ц
```

but it must still activate the preset that was assigned to `W`.

In other words:

```text
English layout:   W key -> preset
Ukrainian layout: Ц key -> same preset
```

The same rule applies to all alphabetic, numeric, and punctuation keys whose produced character changes with the active input source.

Implementation rules:

- use `NSEvent.keyCode` as the canonical identity of a local shortcut;
- match incoming panel `keyDown` events by `keyCode` plus modifier flags;
- do **not** match local shortcuts by `event.characters` or `event.charactersIgnoringModifiers`;
- store the physical key code in `HotKey.keyCode`;
- `displayKey` is presentation metadata only and must never participate in shortcut matching;
- recording a shortcut while any keyboard layout is active must capture the physical key represented by `keyCode`;
- switching keyboard layouts while the GridPanel is open must not change which physical key activates a preset;
- modifier keys such as Command, Option, Control, and Shift are matched separately from the physical key code.

For UI presentation, prefer a stable shortcut label corresponding to the key as it was recorded, for example `W`. It is acceptable to additionally show the character produced by the current input source in the future, but this is optional and must not alter shortcut identity.

This behavior is intentional: local shortcuts are meant to behave like application/game key bindings tied to key positions rather than language-dependent text input.

## 12.2 Local shortcut rules

- plain printable physical keys are allowed;
- shortcuts are identified by physical virtual key code plus modifiers;
- do not conflict with Escape, Return, arrows, or required panel command shortcuts;
- duplicate local preset shortcuts are not allowed when they use the same key code and modifiers, even if their displayed characters differ between keyboard layouts;
- when matched, apply the preset to the captured target and close the panel.

---

# 13. Preset behavior

Each preset contains:

- stable UUID/string ID;
- optional user-visible name;
- scope: `global` or `local`;
- optional hotkey;
- grid area.

Suggested model:

```swift
enum ShortcutScope: String, Codable {
    case global
    case local
}

struct WindowPreset: Codable, Identifiable {
    var id: UUID
    var name: String?
    var scope: ShortcutScope
    var hotKey: HotKey?
    var area: StoredGridArea
}
```

---

## 13.1 Global preset

If a global preset hotkey is pressed while the panel is closed:

```text
global preset hotkey
    ↓
capture current/last external target
    ↓
map preset to target screen visibleFrame
    ↓
apply immediately
```

Do not show the grid panel.

If a global preset hotkey is pressed while the panel is already open:

- apply it to the panel's captured `WindowTarget`;
- close the panel.

This avoids accidentally resolving a different target while the panel owns keyboard interaction.

---

## 13.2 Example Full preset

A Full preset:

```text
x      = 0
y      = 0
width  = columns
height = rows
```

maps to the complete `NSScreen.visibleFrame`.

It must not set the native fullscreen AX attribute and must not move the app to a separate Space.

---

# 14. Settings storage

Path:

```text
~/.config/vindustilpasser/settings.json
```

Create the directory if needed.

Use:

```swift
Codable
JSONEncoder
JSONDecoder
```

Recommended encoder options:

```text
.prettyPrinted
.sortedKeys
```

Write atomically.

Use `Data.write(options: .atomic)` or an equivalent temp-file-plus-rename implementation.

Do not keep settings in `UserDefaults` as the canonical store.

---

## 14.1 Settings schema

Initial schema:

```json
{
  "version": 1,
  "general": {
    "showMenuBarIcon": true,
    "activationHotKey": {
      "keyCode": 103,
      "modifiers": ["command"],
      "displayKey": "F11"
    }
  },
  "grid": {
    "columns": 8,
    "rows": 8
  },
  "presets": [
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "name": "Full",
      "scope": "global",
      "hotKey": {
        "keyCode": 109,
        "modifiers": ["command"],
        "displayKey": "F10"
      },
      "area": {
        "x": 0,
        "y": 0,
        "width": 8,
        "height": 8,
        "columns": 8,
        "rows": 8
      }
    },
    {
      "id": "00000000-0000-0000-0000-000000000002",
      "name": "Left Half",
      "scope": "local",
      "hotKey": {
        "keyCode": 18,
        "modifiers": [],
        "displayKey": "1"
      },
      "area": {
        "x": 0,
        "y": 0,
        "width": 4,
        "height": 8,
        "columns": 8,
        "rows": 8
      }
    }
  ]
}
```

Exact key codes in defaults should be verified on macOS during implementation rather than blindly copied from this example.

---

## 14.2 Settings migration

Include top-level:

```json
"version": 1
```

Create a simple migration layer now even though there is only version 1.

Unknown/missing optional keys should not crash startup.

If the file is invalid:

- log the error;
- preserve the invalid file;
- load in-memory defaults;
- do not silently overwrite the broken file until the user changes a setting.

---

# 15. Settings window

Use a normal `NSWindow`, created programmatically.

When opening Settings:

1. if GridPanel is visible, cancel it without applying;
2. call `NSApp.activate(ignoringOtherApps: true)`;
3. show/make-key the Settings window.

The app still must not gain a Dock icon.

Use an `NSTabViewController` or `NSTabView`.

Required tabs:

```text
General
Grid
Shortcuts
```

No Appearance tab is required for v1.

---

## 15.1 General tab

Controls:

```text
Activation shortcut       [ shortcut recorder ]

[ ] Show icon in menu bar

Accessibility:
    Granted
or
    Permission required
```

If permission is missing, provide a button that triggers the normal Accessibility permission request and/or guides the user to Privacy & Security.

Do not manipulate TCC directly.

Safety rule:

If `Show icon in menu bar` is being turned off, require a valid registered activation shortcut. Do not allow a configuration that makes the app effectively inaccessible.

---

## 15.2 Grid tab

Controls:

```text
Columns: [ 8 ]
Rows:    [ 8 ]

Preview of the grid

Information:
Hold Option while the panel is open for 16×16 precision.
```

The multiplier is fixed at 2 in v1.

Changes should update settings immediately once validated.

---

## 15.3 Shortcuts tab

Show a list/table of presets.

Each row shows:

- area thumbnail;
- optional name;
- scope;
- shortcut.

Example conceptual table:

```text
Area       Name         Scope    Shortcut
[preview]  Full         Global   ⌘F10
[preview]  Left Half    Local    1
[preview]  Right Half   Local    2
```

Provide:

```text
+ Add
- Delete
Edit
```

The preset area editor should reuse the same grid model and grid drawing component used by the main panel.

Do not implement a second incompatible grid system.

---

# 16. Hotkey recorder

Implement a custom AppKit view/control.

Behavior:

- click/focus enters recording mode;
- next valid key combination becomes the candidate shortcut;
- Escape cancels recording;
- Delete/Backspace clears an optional shortcut;
- display macOS modifier glyphs;
- preserve the physical key code;
- keep `charactersIgnoringModifiers`/display label for presentation;
- validate according to global/local scope;
- report conflicts immediately.

Do not rely on a text field accepting literal characters.

---

# 17. Menu-bar status item

Use:

```swift
NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
```

Use an SF Symbol for the template image if available.

Suggested menu:

```text
Open vindustilpasser
Settings…
About vindustilpasser
────────────────────
Quit
```

Actions:

- Open -> same coordinator command as activation hotkey;
- Settings -> normal Settings window;
- About -> About panel/window;
- Quit -> terminate application.

The menu-bar item is controlled by settings and can be created/removed at runtime.

When disabled:

```swift
NSStatusBar.system.removeStatusItem(...)
```

No restart is required.

---

# 18. About

For v1, the standard AppKit About panel is acceptable:

```swift
NSApp.orderFrontStandardAboutPanel(...)
```

Populate version/build information through `Info.plist`.

It is opened from the status-menu item.

Cmd+Q must still quit while About is visible.

A custom About window can replace the standard panel later without changing the rest of the architecture.

---

# 19. Command routing

Create one central coordinator and command router.

Recommended classes:

```text
AppCoordinator
CommandRouter
```

Do not let every UI object manipulate every other subsystem directly.

Suggested responsibilities:

## AppCoordinator

Owns:

- Accessibility permission controller;
- external application tracker;
- WindowManager;
- GridPanelController;
- HotKeyManager;
- SettingsStore;
- SettingsWindowController;
- StatusItemController.

## CommandRouter

Provides high-level commands:

```text
toggleGridPanel()
openSettings()
openAbout()
quit()
applyPreset(id:)
```

The same command must be used regardless of whether the source is:

- global hotkey;
- status menu;
- local panel key event;
- Settings action.

---

# 20. Application state

Keep the behavior close to a small explicit state machine.

Conceptual states:

```text
idle
panelOpen(WindowTarget)
settingsOpen
aboutOpen
```

Do not over-engineer this into a large framework, but keep enough explicit state to avoid target-window confusion.

Important transitions:

```text
idle
  -> activation
  -> panelOpen(target)

panelOpen
  -> Escape
  -> idle

panelOpen
  -> activation hotkey
  -> idle

panelOpen
  -> Enter / mouseUp
  -> apply target
  -> idle

panelOpen
  -> local preset
  -> apply target
  -> idle

panelOpen
  -> Cmd+,
  -> cancel panel
  -> settingsOpen

any vindustilpasser UI open
  -> Cmd+Q
  -> terminate
```

---

# 21. App-wide command keys

Because the app intentionally has no normal main menu, do not depend on standard application menu key equivalents.

Install scoped/local event handling for:

```text
Cmd+,
Cmd+Q
```

Only consume these shortcuts when vindustilpasser itself is presenting UI:

- GridPanel visible;
- Settings window key/visible;
- About visible.

Do not globally steal Cmd+Q or Cmd+, from other applications when vindustilpasser UI is closed.

---

# 22. Project structure

Use this structure unless implementation details justify a small adjustment:

```text
vindustilpasser/
├── Package.swift
├── Makefile
├── .gitignore
├── README.md
├── Resources/
│   ├── Info.plist
│   └── AppIcon.icns              # optional initially
├── scripts/
│   └── sign-app.sh
├── Sources/
│   └── vindustilpasser/
│       ├── main.swift
│       ├── Application/
│       │   ├── AppDelegate.swift
│       │   ├── AppCoordinator.swift
│       │   ├── CommandRouter.swift
│       │   └── ExternalApplicationTracker.swift
│       ├── Accessibility/
│       │   ├── AccessibilityPermission.swift
│       │   ├── AXHelpers.swift
│       │   ├── AXWindow.swift
│       │   ├── WindowManager.swift
│       │   └── WindowTarget.swift
│       ├── Geometry/
│       │   ├── ScreenGeometry.swift
│       │   ├── GridGeometry.swift
│       │   ├── GridSelection.swift
│       │   └── StoredGridArea.swift
│       ├── HotKeys/
│       │   ├── HotKey.swift
│       │   ├── HotKeyManager.swift
│       │   ├── HotKeyModifiers.swift
│       │   └── HotKeyRecorderView.swift
│       ├── Panel/
│       │   ├── GridPanel.swift
│       │   ├── GridPanelController.swift
│       │   └── GridView.swift
│       ├── Preferences/
│       │   ├── PreferencesWindowController.swift
│       │   ├── GeneralPreferencesViewController.swift
│       │   ├── GridPreferencesViewController.swift
│       │   ├── ShortcutsPreferencesViewController.swift
│       │   └── PresetEditorController.swift
│       ├── Settings/
│       │   ├── AppSettings.swift
│       │   ├── SettingsMigration.swift
│       │   └── SettingsStore.swift
│       ├── StatusItem/
│       │   └── StatusItemController.swift
│       └── Utilities/
│           └── Logger.swift
└── Tests/
    └── vindustilpasserTests/
        ├── GridGeometryTests.swift
        ├── ScreenGeometryTests.swift
        └── SettingsTests.swift
```

---

# 23. `Package.swift`

Create an executable Swift package.

Conceptually:

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "vindustilpasser",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "vindustilpasser",
            targets: ["vindustilpasser"]
        )
    ],
    targets: [
        .executableTarget(
            name: "vindustilpasser"
        ),
        .testTarget(
            name: "vindustilpasserTests",
            dependencies: ["vindustilpasser"]
        )
    ]
)
```

If testing executable-internal types becomes awkward, move reusable non-UI logic into an internal library target such as `VindustilpasserCore` and let the executable depend on it.

Prefer that structure if it substantially improves testability.

No third-party package dependencies are required.

---

# 24. App entry point

Use a programmatic AppKit entry point.

Conceptually:

```swift
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

`AppDelegate.applicationDidFinishLaunching` creates the coordinator, loads settings, installs hotkeys/status item, starts external-app tracking, and remains otherwise invisible.

Use `@MainActor` for UI/coordinator types.

Handle Carbon callbacks carefully under Swift concurrency and route them to the main actor.

---

# 25. `Info.plist`

Create `Resources/Info.plist`.

Minimum conceptual contents:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>vindustilpasser</string>

    <key>CFBundleIdentifier</key>
    <string>com.local.vindustilpasser</string>

    <key>CFBundleName</key>
    <string>vindustilpasser</string>

    <key>CFBundleDisplayName</key>
    <string>vindustilpasser</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>

    <key>CFBundleVersion</key>
    <string>1</string>

    <key>LSUIElement</key>
    <true/>

    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>

    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

The bundle identifier is part of application identity. Once Accessibility permission has been granted, do not casually change it.

No Accessibility usage-description plist key is required for this AX client workflow.

No sandbox entitlements file is required.

---

# 26. Build system

The project must build without full Xcode.

Required tools are those available from Command Line Tools for Xcode plus normal macOS system commands:

```text
swift
swiftc
swift package
codesign
security
plutil
ditto
hdiutil
```

No `xcodebuild` is required.

Build the Swift executable with SwiftPM, then manually assemble a `.app` bundle.

Result:

```text
build/
└── vindustilpasser.app/
    └── Contents/
        ├── Info.plist
        ├── MacOS/
        │   └── vindustilpasser
        └── Resources/
            └── AppIcon.icns       # only if present
```

Sign only after every file has been copied into the app bundle.

---

# 27. Code signing and Accessibility permission persistence

This point is important.

## 27.1 Pure ad-hoc signing

For a local build, this is sufficient to launch:

```bash
codesign --force --sign - build/vindustilpasser.app
```

However, a pure ad-hoc signature does **not** provide a stable code identity across rebuilt binary versions. macOS privacy/TCC systems may therefore ask for authorization again after a rebuild.

So:

- ad-hoc signing must remain supported as a fallback;
- it cannot be relied on for persistent Accessibility authorization across rebuilds.

---

## 27.2 Preferred local-development signing mode

To make macOS recognize successive builds as the same local application, support a persistent local **self-signed Code Signing identity**.

This does not require:

- an Apple Developer account;
- Developer ID;
- notarization;
- full Xcode.

One-time setup may be done with the built-in Keychain Access Certificate Assistant:

```text
Name:          vindustilpasser Local Development
Identity Type: Self Signed Root
Certificate:   Code Signing
```

Use a long validity period for this local-only certificate.

The private key lives in the user's login Keychain.

The build script automatically looks for this identity.

If it exists:

```text
sign with "vindustilpasser Local Development"
```

If it does not exist:

```text
fall back to ad-hoc signing
```

and print a clear warning that Accessibility permission may need to be granted again after the next rebuild.

The build process itself remains fully command-line-only.

---

## 27.3 Stable application identity rules

To maximize permission persistence, keep all of these stable:

```text
Bundle identifier
Signing certificate/identity
Application name
Deployment path
```

Most importantly:

```text
CFBundleIdentifier = com.local.vindustilpasser
signing identity   = vindustilpasser Local Development
```

Do not generate a new self-signed certificate on every build.

Do not delete/recreate the signing identity in `make clean`.

---

## 27.4 `.local-signing/`

Create a gitignored directory:

```text
.local-signing/
```

It may contain non-source local metadata such as:

```text
identity-name
certificate-fingerprint
designated-requirement.txt
```

If an exported `.p12` backup is ever placed there, it must remain gitignored and should have restrictive permissions.

The actual normal private key should live in Keychain, not in the Git repository.

After the first successful build signed by the persistent local identity, capture the app's designated requirement with:

```bash
codesign -d -r- build/vindustilpasser.app
```

Store a normalized copy in:

```text
.local-signing/designated-requirement.txt
```

On later persistent-identity builds, compare the current designated requirement with the stored one.

If it changes unexpectedly, print a warning because macOS may consider the app a different identity for privacy permissions.

Do not perform this equality warning for pure ad-hoc builds because their identity is expected to change with the code.

---

## 27.5 Do not promise absolute TCC persistence

Treat stable local signing as the correct best-effort mechanism, not as a way to override macOS security policy.

macOS may still require reauthorization after:

- explicit user permission reset;
- certificate deletion/change;
- bundle identifier change;
- moving between materially different signing identities;
- major security-policy changes;
- manual removal from Accessibility settings.

The application must never try to silently re-grant itself permission.

---

# 28. `scripts/sign-app.sh`

Implement a signing helper.

Inputs:

```text
app bundle path
bundle identifier
```

Configuration:

```text
LOCAL_SIGNING_IDENTITY_NAME="vindustilpasser Local Development"
```

Algorithm:

1. check whether the persistent signing identity is present:

```bash
security find-identity -v -p codesigning
```

2. if found:
   - sign using that identity;
   - use `--timestamp=none`;
   - do not use Hardened Runtime for this local-only v1 unless it becomes necessary later;
   - verify signature;
   - capture/compare designated requirement.

3. if not found:
   - sign with `-` (ad-hoc);
   - verify signature;
   - print a warning about TCC permission persistence.

Do not use `codesign --deep` as a substitute for correct bundle signing.

There is currently only one executable. If nested signed code is added later, sign nested code first and the outer app last.

Suggested verification:

```bash
codesign --verify --strict --verbose=2 "$APP"
codesign -d -r- "$APP"
```

---

# 29. Required Makefile

Create a Makefile with these public targets:

```text
build
clean
deploy
build-dmg
```

The first three retain their original behavior:

- `build` builds and signs the local application;
- `clean` removes build products and temporary files, but preserves local signing state;
- `deploy` builds, signs, and copies the application to the deployment directory.

`build-dmg` is intentionally different:

- it creates a DMG for manually distributing the application;
- the `.app` inside that DMG must be **unsigned**;
- the DMG itself must also be **unsigned**;
- it must not invoke `scripts/sign-app.sh`;
- it must not modify or remove the locally signed app produced by `make build`, if one already exists.

To avoid accidental signing, `build-dmg` should assemble its own application bundle in a separate staging directory rather than depending on the public `build` target.

A recommended implementation is:

```make
APP_NAME := vindustilpasser
PRODUCT_NAME := vindustilpasser
BUNDLE_ID := com.local.vindustilpasser

BUILD_ROOT := build

APP_BUNDLE := $(BUILD_ROOT)/$(APP_NAME).app
CONTENTS := $(APP_BUNDLE)/Contents
MACOS_DIR := $(CONTENTS)/MacOS
RESOURCES_DIR := $(CONTENTS)/Resources

DMG_NAME := $(APP_NAME).dmg
DMG_PATH := $(BUILD_ROOT)/$(DMG_NAME)
DMG_STAGE := $(BUILD_ROOT)/dmg-stage
DMG_APP := $(DMG_STAGE)/$(APP_NAME).app
DMG_CONTENTS := $(DMG_APP)/Contents
DMG_MACOS_DIR := $(DMG_CONTENTS)/MacOS
DMG_RESOURCES_DIR := $(DMG_CONTENTS)/Resources

.PHONY: build clean deploy build-dmg

build:
	@set -eu; \
	echo "==> Building $(PRODUCT_NAME)"; \
	swift build -c release; \
	rm -rf "$(APP_BUNDLE)"; \
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"; \
	BIN_DIR="$$(swift build -c release --show-bin-path)"; \
	cp "$$BIN_DIR/$(PRODUCT_NAME)" "$(MACOS_DIR)/$(PRODUCT_NAME)"; \
	cp "Resources/Info.plist" "$(CONTENTS)/Info.plist"; \
	if [ -f "Resources/AppIcon.icns" ]; then \
		cp "Resources/AppIcon.icns" "$(RESOURCES_DIR)/AppIcon.icns"; \
	fi; \
	chmod 755 "$(MACOS_DIR)/$(PRODUCT_NAME)"; \
	./scripts/sign-app.sh "$(APP_BUNDLE)" "$(BUNDLE_ID)"; \
	/usr/bin/codesign --verify --strict --verbose=2 "$(APP_BUNDLE)"; \
	echo "==> Built $(APP_BUNDLE)"

clean:
	@set -eu; \
	echo "==> Cleaning build outputs"; \
	rm -rf "$(BUILD_ROOT)" ".build"; \
	echo "==> Preserved .local-signing and Keychain signing identity"

deploy: build
	@set -eu; \
	if [ -n "$${DEPLOY_DIR:-}" ]; then \
		DEST_DIR="$$DEPLOY_DIR"; \
	elif [ -d "$(HOME)/Applications" ]; then \
		DEST_DIR="$(HOME)/Applications"; \
	else \
		DEST_DIR="/Applications"; \
	fi; \
	DEST_APP="$$DEST_DIR/$(APP_NAME).app"; \
	echo "==> Deploying to $$DEST_APP"; \
	if [ -w "$$DEST_DIR" ]; then \
		rm -rf "$$DEST_APP"; \
		/usr/bin/ditto "$(APP_BUNDLE)" "$$DEST_APP"; \
	else \
		sudo rm -rf "$$DEST_APP"; \
		sudo /usr/bin/ditto "$(APP_BUNDLE)" "$$DEST_APP"; \
	fi; \
	echo "==> Deployed $$DEST_APP"

build-dmg:
	@set -eu; \
	echo "==> Building unsigned DMG distribution"; \
	swift build -c release; \
	rm -rf "$(DMG_STAGE)" "$(DMG_PATH)"; \
	mkdir -p "$(DMG_MACOS_DIR)" "$(DMG_RESOURCES_DIR)"; \
	BIN_DIR="$$(swift build -c release --show-bin-path)"; \
	cp "$$BIN_DIR/$(PRODUCT_NAME)" "$(DMG_MACOS_DIR)/$(PRODUCT_NAME)"; \
	cp "Resources/Info.plist" "$(DMG_CONTENTS)/Info.plist"; \
	if [ -f "Resources/AppIcon.icns" ]; then \
		cp "Resources/AppIcon.icns" "$(DMG_RESOURCES_DIR)/AppIcon.icns"; \
	fi; \
	chmod 755 "$(DMG_MACOS_DIR)/$(PRODUCT_NAME)"; \
	if /usr/bin/codesign -dv "$(DMG_APP)" >/dev/null 2>&1; then \
		echo "ERROR: DMG staging app unexpectedly has a code signature"; \
		exit 1; \
	fi; \
	/usr/bin/hdiutil create \
		-volname "$(APP_NAME)" \
		-srcfolder "$(DMG_STAGE)" \
		-ov \
		-format UDZO \
		"$(DMG_PATH)"; \
	echo "==> Built unsigned DMG $(DMG_PATH)"
```

Codex may refactor repeated bundle-assembly commands into private Make targets or shell helpers, but preserve the public target behavior exactly.

---

## 29.1 `make build`

Must:

1. run Swift release compilation;
2. create a fresh app bundle;
3. copy `Info.plist`;
4. copy optional resources;
5. sign the completed bundle;
6. verify the signature;
7. leave the final app at:

```text
build/vindustilpasser.app
```

---

## 29.2 `make clean`

Must remove:

```text
build/
.build/
temporary generated build artifacts
DMG staging files
generated DMG files
```

Must **not** remove:

```text
.local-signing/
the local signing identity in Keychain
~/.config/vindustilpasser/settings.json
the deployed application
```

The intention is that a clean rebuild must still use the same persistent signing identity.

---

## 29.3 `make deploy`

Must depend on `build`.

Destination rule:

```text
if DEPLOY_DIR is explicitly supplied:
    use DEPLOY_DIR
else if ~/Applications exists:
    ~/Applications/vindustilpasser.app
else:
    /Applications/vindustilpasser.app
```

Do not automatically create `~/Applications`, because the required default behavior is to use `/Applications` when that directory does not already exist.

If `/Applications` requires elevation, use `sudo` only for the copy/removal operation.

Do not sign after copying; deploy the already signed bundle unchanged.

Do not automatically launch the app unless a later requirement explicitly asks for it.

For stable TCC behavior, the user should normally continue deploying to the same destination path after granting Accessibility permission.

Example override:

```bash
DEPLOY_DIR=/some/path make deploy
```

---

## 29.4 `make build-dmg`

`build-dmg` creates an **unsigned** disk image intended for manual distribution.

Required output:

```text
build/vindustilpasser.dmg
```

The application inside the image must also be unsigned.

Required behavior:

1. compile the release executable with SwiftPM;
2. create a separate temporary DMG staging directory;
3. assemble a fresh `vindustilpasser.app` inside that staging directory;
4. copy `Info.plist` and optional resources;
5. **do not call `scripts/sign-app.sh`;**
6. **do not run ad-hoc signing;**
7. verify that the staged application has no code signature;
8. create a compressed read-only DMG with `/usr/bin/hdiutil`;
9. remove or leave the temporary staging directory only according to normal build-output policy; `make clean` must remove it;
10. leave the generated disk image at:

```text
build/vindustilpasser.dmg
```

Use a compressed UDZO image:

```bash
/usr/bin/hdiutil create \
    -volname "vindustilpasser" \
    -srcfolder "build/dmg-stage" \
    -ov \
    -format UDZO \
    "build/vindustilpasser.dmg"
```

The v1 DMG does not need:

- code signing;
- notarization;
- stapling;
- a custom background;
- Finder window layout metadata;
- an `/Applications` symlink;
- a license dialog.

Those can be added later if explicitly requested.

Important distinction:

```text
make build
    -> signed local-development app

make deploy
    -> signed local-development app copied to deployment location

make build-dmg
    -> separate unsigned app packed into an unsigned DMG
```

`build-dmg` must not depend on `build`, because `build` deliberately signs its output.

If `build/vindustilpasser.app` already exists from a previous `make build`, `make build-dmg` must leave it untouched.

---

# 30. `.gitignore`

Include at least:

```gitignore
.build/
build/
.local-signing/
.DS_Store
```

Do not ignore source settings schemas or `Resources/Info.plist`.

Do not commit exported private signing keys/certificates.

---

# 31. Accessibility permission UX

At startup:

- call `AXIsProcessTrusted()` without forcing a prompt;
- allow the app to initialize its status item/settings/hotkeys even if permission is absent.

On the first window-control action:

1. check trust;
2. if not trusted, call `AXIsProcessTrustedWithOptions` with prompt enabled;
3. do not attempt the resize;
4. show concise guidance that Accessibility access is required;
5. let the user retry after enabling it.

Settings should always show current permission status.

Do not poll aggressively.

A short refresh when Settings becomes key is enough.

---

# 32. Status and no-Dock behavior

Set:

```xml
<key>LSUIElement</key>
<true/>
```

and also use:

```swift
NSApp.setActivationPolicy(.accessory)
```

as appropriate.

Do not create a standard main application menu.

The application should not appear in the Dock during normal use, including when Settings is open.

---

# 33. Local panel event handling

While GridPanel is visible:

- it must receive keyboard input even though it is non-activating;
- install/remove local event monitors only for the panel lifetime if needed;
- `flagsChanged` updates Option fine mode;
- `keyDown` routes arrows, Enter, Escape, local presets, Cmd+,, Cmd+Q.

Do not leave stale local event monitors installed after panel close.

Always remove event-monitor tokens during teardown.

---

# 34. Panel lifecycle details

When showing:

```text
capture target
configure panel screen
configure selection
order panel front
make it key without normal application activation
focus grid interaction
```

When closing:

```text
remove local event monitor
clear drag state
clear fine-mode state
clear WindowTarget
order panel out
```

On cancellation, never write an AX frame.

On successful apply, clear the captured target after the operation completes.

---

# 35. Settings live updates

Settings changes should take effect immediately after validation.

Examples:

- menu-bar icon toggle -> create/remove status item;
- activation hotkey -> re-register;
- global preset hotkey -> re-register;
- grid dimensions -> next panel uses new dimensions;
- preset add/delete/edit -> update in-memory settings and global registrations.

Write settings atomically after each accepted change.

If an external edit changes `settings.json` while the app runs, v1 does not need to live-reload it.

---

# 36. UI architecture

Prefer small AppKit view controllers and custom views rather than one giant controller.

Programmatic Auto Layout is acceptable.

Avoid excessive custom drawing outside `GridView` and small preset thumbnails.

Use system controls:

```text
NSButton
NSTextField
NSSegmentedControl / NSPopUpButton
NSTableView
NSTabViewController
NSStepper
NSScrollView
```

Use standard accessibility labels on vindustilpasser's own controls.

---

# 37. Logging

Use `os.Logger`.

Suggested subsystem:

```text
com.local.vindustilpasser
```

Suggested categories:

```text
app
accessibility
hotkeys
panel
settings
window
```

Log:

- permission state changes;
- global shortcut registration failures;
- AX errors;
- target app/window resolution;
- requested vs actual window frame at debug level;
- settings parse errors;
- signing is handled by build scripts, not runtime logs.

Do not log sensitive user content or window titles by default.

Application names/PIDs at debug level are acceptable.

---

# 38. Tests

## 38.1 Unit tests

Write tests for logic that does not require live macOS application windows.

### Grid geometry tests

Test:

- full area;
- left half;
- right half;
- quarter;
- arbitrary rational preset;
- adjacent areas share edges;
- no visual gap enters geometry;
- normal 8×8 vs fine 16×16 behavior;
- clamping movement;
- clamping resize.

### Screen coordinate tests

Use synthetic rectangles to test:

- primary screen;
- screen to left;
- screen to right;
- screen above;
- screen below;
- negative coordinates;
- AX -> AppKit -> AX round trip.

### Settings tests

Test:

- default creation;
- JSON encode/decode round trip;
- missing optional preset name;
- version field;
- invalid JSON fallback without destructive overwrite.

### Hotkey model tests

Test:

- modifier encoding;
- conflict detection;
- global bare-printable rejection;
- local bare-printable acceptance.

---

## 38.2 Manual integration tests

Perform on a real macOS machine.

Test with several normal applications, for example:

```text
Finder
Terminal
Safari
TextEdit
System Settings
```

Scenarios:

1. first run without Accessibility permission;
2. grant permission;
3. activation hotkey opens panel;
4. panel appears on correct display;
5. target window remains the external window captured before panel display;
6. Escape makes no changes;
7. activation hotkey closes open panel without changes;
8. mouse drag changes only highlight;
9. mouse release applies;
10. arrows move selection;
11. Shift+arrows resize;
12. Option changes precision;
13. Enter applies;
14. local preset applies and closes;
15. global preset works with no panel;
16. Full preset fills `visibleFrame` but does not enter native fullscreen;
17. Settings opens with Cmd+, from panel;
18. Cmd+Q quits while panel is visible;
19. Cmd+Q quits while Settings is visible;
20. status icon toggle works immediately;
21. About opens from status menu;
22. no Dock icon appears;
23. no ordinary app menu is required;
24. two-monitor arrangement left/right;
25. two-monitor arrangement above/below;
26. Dock positioned on left/right/bottom;
27. target window spans monitors;
28. target app closes while panel is open;
29. target window closes while panel is open;
30. fixed-size/non-resizable window fails cleanly;
31. native fullscreen target is rejected cleanly;
32. record local preset shortcut `W` using an English layout, switch to Ukrainian, press the physical key that produces `Ц`, and verify the same preset activates;
33. switch keyboard layout while the GridPanel is already open and verify local shortcuts continue matching by physical key code.

---

# 39. Critical signing/TCC integration test

This test verifies the development-signing goal.

## Persistent local identity case

1. create the self-signed Code Signing identity once;
2. run `make deploy`;
3. launch the deployed app;
4. grant Accessibility permission;
5. verify resizing works;
6. modify Swift source;
7. run `make clean`;
8. run `make deploy`;
9. launch the deployed app from the same destination;
10. verify that the build uses the same signing identity and designated requirement;
11. verify macOS still reports `AXIsProcessTrusted() == true`.

If permission is lost:

- inspect:

```bash
codesign -d -r- /path/to/vindustilpasser.app
codesign -dv --verbose=4 /path/to/vindustilpasser.app
security find-identity -v -p codesigning
```

- compare old/new designated requirement;
- verify bundle identifier did not change;
- verify deployment path did not unexpectedly switch between `~/Applications` and `/Applications`.

Do not "solve" the test by programmatically changing TCC.

---

# 40. Build/signing diagnostics

When `make build` completes, print:

```text
built app path
signing mode: local identity or ad-hoc
bundle identifier
```

When using the persistent local identity, also print the signing identity name.

When using ad-hoc signing, print something like:

```text
WARNING: using ad-hoc signing.
Accessibility permission may need to be granted again after a rebuild.
Create the "vindustilpasser Local Development" self-signed Code Signing
identity in Keychain to get a stable local code identity.
```

This warning is intentional and should not be hidden.

---

# 41. Implementation phases for Codex CLI

Implement in the following order.

Do not attempt the entire application in one giant change.

---

## Phase 1 — repository/build skeleton

Create:

```text
Package.swift
Makefile
.gitignore
Resources/Info.plist
scripts/sign-app.sh
Sources/vindustilpasser/main.swift
Sources/vindustilpasser/Application/AppDelegate.swift
```

The Makefile must already expose the four required public targets:

```text
build
clean
deploy
build-dmg
```

Implement a minimal invisible AppKit agent.

Acceptance:

```bash
make clean
make build
open build/vindustilpasser.app
```

The app launches without a Dock icon and stays running.

Verify signature.

---

## Phase 2 — Settings model and storage

Implement:

```text
AppSettings
SettingsStore
SettingsMigration
HotKey data model
StoredGridArea
WindowPreset
```

Implement:

```text
~/.config/vindustilpasser/settings.json
```

with defaults and atomic writes.

Add unit tests.

Acceptance:

- clean first launch uses defaults;
- a settings file is created only when needed/when settings are persisted;
- round trip works;
- invalid file does not get silently destroyed.

---

## Phase 3 — Accessibility layer

Implement:

```text
AccessibilityPermission
AXHelpers
AXWindow
WindowTarget
WindowManager
```

Create a temporary debug command/path if necessary to print the current external window frame.

Acceptance:

- no permission -> clean error/prompt;
- with permission -> current Finder/Terminal window frame can be read;
- frame can be resized through a temporary test path.

Remove temporary debug UI once panel/presets exist.

---

## Phase 4 — Screen geometry

Implement:

```text
ScreenGeometry
target-screen selection
AX/AppKit conversion
```

Add synthetic unit tests and manual multi-monitor checks.

Do not continue until round-trip geometry is trustworthy.

---

## Phase 5 — Grid geometry

Implement:

```text
GridSelection
GridGeometry
StoredGridArea mapping
normal/fine lattice
movement
resizing
```

Add unit tests.

Acceptance:

- 8×8 full/half/quarter mappings are exact;
- fine mode provides 16×16 positions;
- adjacent areas share boundaries.

---

## Phase 6 — GridPanel and GridView

Implement the translucent panel and drawing.

Initially show it from a temporary status-menu action if global hotkeys are not ready.

Acceptance:

- panel centers on requested screen;
- no title bar;
- no Dock icon;
- grid has visual gaps;
- selection highlight renders correctly;
- system dark/light appearance works.

---

## Phase 7 — Mouse/keyboard panel interaction

Implement:

```text
mouseDown
mouseDragged
mouseUp
arrows
Shift+arrows
Option
Enter
Escape
Cmd+,
Cmd+Q
```

Wire mouseUp/Enter to WindowManager.

Acceptance:

- no external resize during preview;
- mouseUp/Enter resize exactly once;
- Escape never changes the target;
- target remains the originally captured AX window.

---

## Phase 8 — Global HotKeyManager

Implement Carbon registration.

Add activation hotkey.

Acceptance:

- shortcut works while another application is active;
- pressing it opens panel;
- pressing it again while panel is open cancels panel;
- no key-event tap is needed.

---

## Phase 9 — Status item and external-app tracker

Implement:

```text
ExternalApplicationTracker
StatusItemController
```

Acceptance:

- Open from status menu targets the last external app;
- icon can be shown/hidden at runtime;
- Quit works.

---

## Phase 10 — Settings window

Implement General and Grid tabs first.

Acceptance:

- Cmd+, from panel cancels panel and opens Settings;
- activation hotkey can be changed;
- status icon can be toggled;
- grid rows/columns can be changed;
- Accessibility state is visible.

---

## Phase 11 — Presets and Shortcuts tab

Implement:

```text
preset list
preset editor
area thumbnail
area grid editor
scope selector
hotkey recorder
global preset registration
local preset matching
```

Acceptance:

- global preset works without panel;
- local preset works only in panel;
- preset applies to correct display;
- Full preset uses visibleFrame, not native fullscreen;
- conflicting hotkeys are rejected.

---

## Phase 12 — About and polish

Implement:

```text
About
error messages
logging
final visual tuning
```

Run all unit and manual tests.

---

## Phase 13 — signing/TCC persistence verification

Test both signing modes.

### Ad-hoc

Verify:

```text
build works
app launches
permission can be granted
```

Do not assume permission survives rebuild.

### Persistent local identity

Verify:

```text
same certificate
same bundle identifier
same designated requirement
same deploy path
permission survives normal source rebuild/deploy
```

### Unsigned DMG

Verify:

```bash
make build-dmg
```

Then verify:

```text
build/vindustilpasser.dmg exists
the DMG mounts successfully
vindustilpasser.app is present inside it
the app inside the DMG has no code signature
the DMG build did not alter build/vindustilpasser.app
```

Document the one-time local signing setup and the unsigned DMG workflow in README.

---

# 42. Important implementation constraints

Codex must follow these constraints during implementation:

1. Do not introduce SwiftUI just because Settings is easier in SwiftUI.
2. Do not add Xcode project files.
3. Do not add third-party dependencies unless explicitly approved later.
4. Do not use private APIs for window resizing.
5. Do not modify the TCC database.
6. Do not make the application sandboxed.
7. Do not perform AX window lookup after the panel has already changed focus.
8. Do not store settings only in UserDefaults.
9. Do not let rendering gaps affect window geometry.
10. Do not enter macOS native fullscreen for the Full preset.
11. Do not resize continuously during grid preview.
12. Do not globally consume printable local-preset keys.
13. Do not let global shortcut conflicts silently replace working shortcuts.
14. Do not remove local signing identity/material in `make clean`.
15. Do not recreate a local signing certificate on every build.
16. Do not move signing to before bundle assembly; signing must be the final build step.
17. Do not automatically create `~/Applications` during deploy.
18. Do not resize vindustilpasser's own Settings/About/Grid windows through the external window manager.
19. Do not sign the application assembled for `make build-dmg`, including ad-hoc signing.
20. Do not make `build-dmg` depend on the signed `build` target.
21. Do not let `build-dmg` overwrite or mutate `build/vindustilpasser.app`.

---

# 43. Suggested internal interfaces

These are guidance, not an absolute API requirement.

```swift
@MainActor
protocol WindowManaging {
    func captureTarget() throws -> WindowTarget
    func apply(appKitRect: CGRect, to target: WindowTarget) throws -> CGRect
}
```

```swift
protocol SettingsStoring {
    func load() throws -> AppSettings
    func save(_ settings: AppSettings) throws
}
```

```swift
@MainActor
protocol GridPanelPresenting {
    var isVisible: Bool { get }
    func show(target: WindowTarget, settings: AppSettings)
    func cancel()
}
```

```swift
@MainActor
protocol HotKeyManaging {
    func apply(settings: AppSettings) throws
    func unregisterAll()
}
```

The important architectural rule is:

```text
Grid/UI does not directly manipulate AX APIs.
Accessibility/WindowManager does not know about AppKit grid drawing.
AppCoordinator connects the two.
```

---

# 44. Expected runtime architecture

```text
                    ┌──────────────────────┐
                    │      HotKeyManager   │
                    └──────────┬───────────┘
                               │
Status Item ───────────────────┤
                               ▼
                    ┌──────────────────────┐
                    │    AppCoordinator    │
                    └───────┬───────┬──────┘
                            │       │
                   ┌────────┘       └─────────────┐
                   ▼                              ▼
        ┌────────────────────┐        ┌────────────────────┐
        │   WindowManager    │        │ GridPanelController│
        │    AXUIElement     │        └──────────┬─────────┘
        └──────────┬─────────┘                   │
                   │                    ┌─────────▼─────────┐
                   │                    │ GridView / model  │
                   │                    └─────────┬─────────┘
                   │                              │
                   └──────────────┬───────────────┘
                                  ▼
                         ┌──────────────────┐
                         │   GridGeometry   │
                         └──────────────────┘

        ┌────────────────────┐
        │   SettingsStore    │
        │   settings.json    │
        └──────────┬─────────┘
                   │
           ┌───────┴─────────┐
           ▼                 ▼
    Preferences         HotKeyManager
```

---

# 45. Definition of done

The first complete version is done when all of the following are true:

- `make build` creates the signed local-development app at `build/vindustilpasser.app`;
- `make clean` removes build outputs, DMG outputs, and temporary staging files but preserves local signing state;
- `make deploy` deploys to `~/Applications` when that directory exists, otherwise `/Applications`;
- `make build-dmg` creates `build/vindustilpasser.dmg`;
- the application inside the DMG is unsigned and the DMG itself is unsigned;
- `make build-dmg` does not mutate an existing signed `build/vindustilpasser.app`;
- full Xcode is not required;
- the app has no Dock icon;
- the app has no ordinary main menu;
- Accessibility permission is requested only through supported macOS mechanisms;
- the app can capture and resize windows of other normal applications;
- activation works through a configurable global hotkey;
- the panel opens on the screen containing the captured target window;
- the panel is borderless, translucent, and floating;
- default grid is 8×8;
- holding Option provides 16×16 precision for an 8×8 grid;
- mouse drag previews only;
- mouse release applies;
- arrows move selection;
- Shift+arrows resize selection;
- Enter applies;
- Escape cancels;
- the activation hotkey cancels an already-open panel;
- Cmd+, opens Settings from the panel;
- Cmd+Q quits while vindustilpasser UI is open;
- menu-bar icon is optional and updates without restart;
- menu-bar menu offers Open, Settings, About, Quit;
- global presets work without opening the panel;
- local presets work only while the panel is open;
- presets store rational grid geometry independently of the current default grid;
- Full preset fills usable screen space but does not invoke native fullscreen;
- settings are stored in `~/.config/vindustilpasser/settings.json`;
- invalid/unresizable windows fail safely;
- multi-monitor geometry works;
- persistent local signing identity is supported;
- pure ad-hoc signing remains available as fallback;
- repeated rebuild/deploy with the same persistent local signing identity is verified not to unnecessarily lose Accessibility authorization under normal conditions.

---

# 46. Apple documentation references

Use these as the authoritative references when implementation details are uncertain:

- Accessibility trust:
  - https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted
  - https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions

- Accessibility UI elements:
  - https://developer.apple.com/documentation/applicationservices/axuielement

- `NSPanel`:
  - https://developer.apple.com/documentation/appkit/nspanel

- `NSWindow.StyleMask.nonactivatingPanel`:
  - https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel

- `LSUIElement`:
  - https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement

- Code signing / designated requirements:
  - https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements
  - https://developer.apple.com/library/archive/technotes/tn2206/

Important signing conclusion for this project:

```text
Ad-hoc signature:
    sufficient to run locally,
    not a reliable stable identity across rebuilt code.

Persistent self-signed Code Signing identity:
    still local-only,
    no Apple Developer account required,
    suitable for keeping a stable designated requirement during development.
```

That distinction should be preserved in the implementation and README.

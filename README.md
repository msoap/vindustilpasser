# vindustilpasser

vindustilpasser is a native macOS menu-bar utility for positioning windows of other applications. It uses AppKit, Accessibility, and Carbon hotkeys. It has no Dock icon or normal application menu.

## Build and run

Requires macOS 13 or later and Xcode Command Line Tools. Full Xcode is not needed.

```sh
make build
open build/vindustilpasser.app
```

`make build` creates `build/vindustilpasser.app` and verifies its signature. This machine's Command Line Tools currently need SwiftPM's native build backend, which the Makefile selects. `make clean` removes build outputs without deleting settings or signing state. `make test` runs the logic tests with the Command Line Tools Swift Testing framework; that framework requires macOS 14 or later for the test runner.

Use `make build-unsigned` for the no-certificate workflow. It ad-hoc signs `build/vindustilpasser.app` without using a Keychain identity, so there is no signing-password prompt. A completely unsigned executable cannot run on Apple silicon; ad-hoc signing is the closest runnable equivalent. This target replaces the same app bundle, so switching between it and `make build` may require granting Accessibility access again. Use `make build` for a stable local signing identity.

To install the signed build, use `make deploy`. It chooses `~/Applications` if that directory exists and `/Applications` otherwise; it does not create `~/Applications`. Set `DEPLOY_DIR=/path` to override. Keep the same destination after granting Accessibility access.

## Use

The default activation shortcut is Command-F11. It opens a grid for the focused window of the current or last active external application. Drag over cells and release the mouse to apply. Arrow keys move the selection; Shift with arrows resizes it from its top-left corner. Hold Option for double grid precision. Return applies; Escape or the activation shortcut cancels. Command-comma opens Settings, Command-W closes the active Settings or About window, and Command-Q quits while vindustilpasser UI is open.

The menu-bar icon opens the grid, Settings, About, and Quit. About links to the project's Github repository. Settings has General, Grid, and Shortcuts toolbar sections. Grid dimension edits also save when leaving Grid or closing Settings; Enter is not required. In Shortcuts, use the arrow keys to select a preset and Return or keypad Enter to edit it. The preset editor opens as a modal sheet; press Escape to cancel it. The default global Command-F10 preset fills the usable screen without entering native fullscreen. Default local `1` and `2` presets place a window in the left or right half. Local shortcuts are bound to physical macOS key codes, so switching keyboard layouts does not change which key activates a preset.

Before controlling windows, grant vindustilpasser Accessibility access in System Settings → Privacy & Security → Accessibility. The app uses the standard macOS permission prompt on the first window action. It never changes permission settings itself. Some native fullscreen, minimized, fixed-size, or application-constrained windows cannot be resized.

Settings live at `~/.config/vindustilpasser/settings.json`. The file is created when a setting is saved. Invalid JSON is preserved and defaults are used in memory until a setting is changed.

## Signing

The preferred local identity is a self-signed **Code Signing** certificate named `vindustilpasser Local Development`. Run `make setup-signing` once to create it in your login Keychain with a trust rule limited to code signing. The private key is generated in a temporary directory, imported into Keychain, and the temporary copy is removed. Alternatively, create the identity once with Keychain Access → Certificate Assistant → Create a Certificate, choosing Self Signed Root and Code Signing. `make build` then signs with that identity and compares its designated requirement to `.local-signing/designated-requirement.txt` on later builds. Keep the certificate, bundle ID (`com.local.vindustilpasser`), and deployment path stable to help Accessibility authorization survive rebuilds. macOS may still require reauthorization after a permission reset or identity change.

If each build asks for the Keychain password, check the dialog text. For “codesign wants to sign using key …”, enter the password and choose **Always Allow** once; **Allow** grants access only for that build. This authorizes `codesign` for the signing key, not every application. For “codesign wants to use the login keychain”, the keychain is locked: unlock it in Keychain Access or run `security unlock-keychain "$HOME/Library/Keychains/login.keychain-db"` and enter the password at the prompt. Do not put the password in the Makefile or disable Keychain protections to suppress the dialog.

If that identity is absent, the build uses ad-hoc signing and prints a warning. Ad-hoc signatures can change identity when the binary changes, so Accessibility authorization may need to be granted again. `make clean` preserves the Keychain identity and `.local-signing` metadata.

After a persistent identity has been used, the build refuses to fall back to ad-hoc signing if that identity becomes unavailable. Unlock or repair the login Keychain and rebuild instead; silently switching signatures would break Accessibility access again.

If an existing Accessibility row stays enabled but the app reports no access after an ad-hoc rebuild, set up the persistent identity, rebuild, quit any running old copy, and grant access to the newly signed app once. The old ad-hoc row can be removed in System Settings. Future builds signed by the same certificate should keep the same designated requirement; do not remove the certificate or switch the app's path.

For an unsigned distributable image, run `make build-dmg`. It creates `build/vindustilpasser.dmg` from a separate unsigned app; the signed local app is untouched. SwiftPM adds a linker signature to arm64 executables, so the DMG target removes it from the staged copy before packaging. The DMG is not signed or notarized.

## Verification

```sh
make test
codesign --verify --strict build/vindustilpasser.app
hdiutil verify build/vindustilpasser.dmg
```

Window-control and permission behavior require hands-on testing with normal apps on a macOS desktop. Also check displays arranged left/right and above/below, Dock positions, application-enforced size limits, and local shortcuts after changing keyboard layout.

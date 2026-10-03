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

Press Command-F11 to open the positioning grid for the active window. Drag across cells and release to move and resize it. Arrow keys move the selection; Shift-arrow keys resize it. Hold Option for a finer grid. Press Return to apply or Escape to cancel.

Command-F10 fills the usable screen without entering macOS fullscreen. Press `1` or `2` while the grid is open to place the window in the left or right half. Change grid size and shortcuts in Settings (Command-comma).

Grant vindustilpasser Accessibility access when prompted, or in System Settings → Privacy & Security → Accessibility. Some apps restrict how their windows can be resized.

## Signing

The preferred local identity is a self-signed **Code Signing** certificate named `vindustilpasser Local Development`. Run `make setup-signing` once to create it in your login Keychain with a trust rule limited to code signing. The private key is generated in a temporary directory, imported into Keychain, and the temporary copy is removed. Alternatively, create the identity once with Keychain Access → Certificate Assistant → Create a Certificate, choosing Self Signed Root and Code Signing. `make build` then signs with that identity and compares its designated requirement to `.local-signing/designated-requirement.txt` on later builds. Keep the certificate, bundle ID (`com.local.vindustilpasser`), and deployment path stable to help Accessibility authorization survive rebuilds. macOS may still require reauthorization after a permission reset or identity change.

If each build asks for the Keychain password, check the dialog text. For “codesign wants to sign using key …”, enter the password and choose **Always Allow** once; **Allow** grants access only for that build. This authorizes `codesign` for the signing key, not every application. For “codesign wants to use the login keychain”, the keychain is locked: unlock it in Keychain Access or run `security unlock-keychain "$HOME/Library/Keychains/login.keychain-db"` and enter the password at the prompt. Do not put the password in the Makefile or disable Keychain protections to suppress the dialog.

If that identity is absent, the build uses ad-hoc signing and prints a warning. Ad-hoc signatures can change identity when the binary changes, so Accessibility authorization may need to be granted again. `make clean` preserves the Keychain identity and `.local-signing` metadata.

After a persistent identity has been used, the build refuses to fall back to ad-hoc signing if that identity becomes unavailable. Unlock or repair the login Keychain and rebuild instead; silently switching signatures would break Accessibility access again.

If an existing Accessibility row stays enabled but the app reports no access after an ad-hoc rebuild, set up the persistent identity, rebuild, quit any running old copy, and grant access to the newly signed app once. The old ad-hoc row can be removed in System Settings. Future builds signed by the same certificate should keep the same designated requirement; do not remove the certificate or switch the app's path.

For an unsigned distributable image, run `make build-dmg`. It creates `build/vindustilpasser.dmg` from a separate unsigned app; the signed local app is untouched. SwiftPM adds a linker signature to arm64 executables, so the DMG target removes it from the staged copy before packaging. The DMG is not signed or notarized.

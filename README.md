# vindustilpasser

<p align="center"><img width="398" height="344" alt="image" src="https://github.com/user-attachments/assets/0e655e34-cf84-4c6b-9095-582f388e2732" /></p>  

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

Command-F10 fills the usable screen without entering macOS fullscreen. Change grid size and add your own presets and shortcuts in Settings (Command-comma).

Grant vindustilpasser Accessibility access when prompted, or in System Settings → Privacy & Security → Accessibility. Some apps restrict how their windows can be resized.

## Settings screenshot

<img width="346" height="300" alt="image" src="https://github.com/user-attachments/assets/d1de26d4-f9b9-4350-ac31-525d0e8ee5a6" />

<img width="346" height="300" alt="image" src="https://github.com/user-attachments/assets/a5a9f17d-2e82-4a56-9bf4-771f032dddde" />

<img width="346" height="300" alt="image" src="https://github.com/user-attachments/assets/e774a8a7-0a63-45e3-94fd-bf9100d0c688" />

<img width="346" height="320" alt="image" src="https://github.com/user-attachments/assets/b8ae4f2f-e0fe-45be-91b7-725f6b05e8a7" />

## Signing

The preferred local identity is a self-signed **Code Signing** certificate named `vindustilpasser Local Development`. Run `make setup-signing` once to create it in your login Keychain with a trust rule limited to code signing. The private key is generated in a temporary directory, imported into Keychain, and the temporary copy is removed. Alternatively, create the identity once with Keychain Access → Certificate Assistant → Create a Certificate, choosing Self Signed Root and Code Signing. `make build` then signs with that identity and compares its designated requirement to `.local-signing/designated-requirement.txt` on later builds. Keep the certificate, bundle ID (`com.local.vindustilpasser`), and deployment path stable to help Accessibility authorization survive rebuilds. macOS may still require reauthorization after a permission reset or identity change.

If each build asks for the Keychain password, check the dialog text. For “codesign wants to sign using key …”, enter the password and choose **Always Allow** once; **Allow** grants access only for that build. This authorizes `codesign` for the signing key, not every application. For “codesign wants to use the login keychain”, the keychain is locked: unlock it in Keychain Access or run `security unlock-keychain "$HOME/Library/Keychains/login.keychain-db"` and enter the password at the prompt. Do not put the password in the Makefile or disable Keychain protections to suppress the dialog.

If that identity is absent, the build uses ad-hoc signing and prints a warning. Ad-hoc signatures can change identity when the binary changes, so Accessibility authorization may need to be granted again. `make clean` preserves the Keychain identity and `.local-signing` metadata.

After a persistent identity has been used, the build refuses to fall back to ad-hoc signing if that identity becomes unavailable. Unlock or repair the login Keychain and rebuild instead; silently switching signatures would break Accessibility access again.

If an existing Accessibility row stays enabled but the app reports no access after an ad-hoc rebuild, set up the persistent identity, rebuild, quit any running old copy, and grant access to the newly signed app once. The old ad-hoc row can be removed in System Settings. Future builds signed by the same certificate should keep the same designated requirement; do not remove the certificate or switch the app's path.

For an unsigned distributable image, run `make build-dmg`. It names the image using the app version in `Resources/Info.plist`, such as `build/vindustilpasser-1.0.0.dmg`. It packages a separate unsigned app; the signed local app is untouched. SwiftPM adds a linker signature to arm64 executables, so the DMG target removes it from the staged copy before packaging. The DMG is not signed or notarized.

## Q&A

1. **What inspired vindustilpasser?** 

 - [Divvy](https://mizage.com/divvy/), a grid-based window manager. Its [Mac App Store version](https://apps.apple.com/us/app/divvy-window-manager/id413857545) was last updated in 2019, and it's still Intel-only.

2. **What does the name mean?** 

 - Try translating from Norwegian.

3. **What's the best way to install it?**

 - Clone this repository, then run `make build && make deploy` from its directory.

4. **How do I install the Xcode Command Line Tools?**

 - Run `xcode-select --install` in Terminal and follow the prompt.

5. **Why does macOS block the app from the DMG?**

 - The DMG contains an unsigned, unnotarized app. If you trust the download, copy the app to Applications and try opening it. Then go to System Settings → Privacy & Security → **Open Anyway** and confirm. See [Apple's guidance](https://support.apple.com/en-ie/102445).

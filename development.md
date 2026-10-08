# Development

## Requirements

Use macOS 13 or later with Xcode Command Line Tools; full Xcode is not required. Install the tools with `xcode-select --install` if needed. The Swift Testing runner used by `make test` requires macOS 14 or later.

## Build, run, and install

```sh
make build
open build/vindustilpasser.app
```

`make build` creates `build/vindustilpasser.app` and verifies its signature. The Makefile selects SwiftPM's native build backend for compatibility with this machine's Command Line Tools. `make clean` removes build outputs without deleting settings or signing state. `make test` compiles and runs the logic tests.

To install the signed build, clone this repository and run `make build && make deploy` from its directory. `make deploy` chooses `~/Applications` if that directory exists and `/Applications` otherwise; it does not create `~/Applications`. Set `DEPLOY_DIR=/path` to override. Keep the same destination after granting Accessibility access.

Use `make build-unsigned` for the no-certificate workflow. It ad-hoc signs `build/vindustilpasser.app` without using a Keychain identity, so there is no signing-password prompt. A completely unsigned executable cannot run on Apple silicon; ad-hoc signing is the closest runnable equivalent. This target replaces the same app bundle, so switching between it and `make build` may require granting Accessibility access again. Use `make build` for a stable local signing identity.

The app icon source is `Resources/AppIcon.svg`. After editing it, run `make icon` to regenerate the checked-in `Resources/AppIcon.icns`; this requires `rsvg-convert` from `librsvg` (`brew install librsvg`). Ordinary builds use the existing `.icns` file and do not need `librsvg`.

## Signing

The preferred local identity is a self-signed **Code Signing** certificate named `vindustilpasser Local Development`. Run `make setup-signing` once to create it in your login Keychain with a trust rule limited to code signing. The private key is generated in a temporary directory, imported into Keychain, and the temporary copy is removed. Alternatively, create the identity once with Keychain Access → Certificate Assistant → Create a Certificate, choosing Self Signed Root and Code Signing. `make build` then signs with that identity and compares its designated requirement to `.local-signing/designated-requirement.txt` on later builds. Keep the certificate, bundle ID (`com.local.vindustilpasser`), and deployment path stable to help Accessibility authorization survive rebuilds. macOS may still require reauthorization after a permission reset or identity change.

If each build asks for the Keychain password, check the dialog text. For “codesign wants to sign using key …”, enter the password and choose **Always Allow** once; **Allow** grants access only for that build. This authorizes `codesign` for the signing key, not every application. For “codesign wants to use the login keychain”, the keychain is locked: unlock it in Keychain Access or run `security unlock-keychain "$HOME/Library/Keychains/login.keychain-db"` and enter the password at the prompt. Do not put the password in the Makefile or disable Keychain protections to suppress the dialog.

If that identity is absent, the build uses ad-hoc signing and prints a warning. Ad-hoc signatures can change identity when the binary changes, so Accessibility authorization may need to be granted again. `make clean` preserves the Keychain identity and `.local-signing` metadata.

After a persistent identity has been used, the build refuses to fall back to ad-hoc signing if that identity becomes unavailable. Unlock or repair the login Keychain and rebuild instead; silently switching signatures would break Accessibility access again.

If an existing Accessibility row stays enabled but the app reports no access after an ad-hoc rebuild, set up the persistent identity, rebuild, quit any running old copy, and grant access to the newly signed app once. The old ad-hoc row can be removed in System Settings. Future builds signed by the same certificate should keep the same designated requirement; do not remove the certificate or switch the app's path.

## Disk images

For a distributable image, run `make build-dmg`. It names the image using the app version in `Resources/Info.plist`, such as `build/vindustilpasser-N.N.N.dmg`. It packages a separate ad-hoc signed app with the app icon and gives the mounted volume the same icon; the downloaded `.dmg` file keeps Finder's standard disk-image icon. The locally signed app is untouched. The DMG itself is not signed or notarized. Ad-hoc signing lets the app run on Apple silicon, but does not establish a trusted developer identity; Accessibility authorization may need renewal after updates.

If macOS blocks the app from a DMG you trust, copy the app to Applications and try opening it. Then go to System Settings → Privacy & Security → **Open Anyway** and confirm. See [Apple's guidance](https://support.apple.com/en-ie/102445).

## Releases

Set a specific app version with `make new-version VERSION=1.2.3`, or bump the current version with `make inc-patch-version`, `make inc-minor-version`, or `make inc-major-version`. These commands update `CFBundleShortVersionString` in `Resources/Info.plist`; minor and major bumps reset lower components to zero.

Pushing a tag named `vN.N.N` or `vN.N.N-beta-NNN` runs the GitHub Actions release workflow. The numeric part must match `CFBundleShortVersionString` in `Resources/Info.plist`. Beta tags create GitHub prereleases; the plist version remains numeric because macOS requires three period-separated integers. The workflow tests and builds on Apple silicon and Intel runners, then attaches an ad-hoc signed DMG for each architecture to the GitHub Release. No signing certificate or Apple notarization credentials are needed.

Commit the version change and workflow before tagging. For example, when the plist version is `1.1.1`, run `git tag v1.1.1 && git push origin v1.1.1`. For a beta of the same version, use a tag such as `v1.1.1-beta-001`.

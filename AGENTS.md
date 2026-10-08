# Repository Guidelines

## Project Structure & Module Organization

`Sources/vindustilpasser/` contains the macOS menu-bar app. Keep changes in the relevant area: `Accessibility/` for window access, `Geometry/` for grid math, `HotKeys/` for shortcuts, `Panel/` for the selection overlay, `Preferences/` for settings UI, and `Settings/` for persistence. `Application/` coordinates these components; `StatusItem/` owns the menu-bar UI. Logic tests live in `Tests/vindustilpasserTests/`. `Resources/Info.plist` supplies bundle metadata, `scripts/` handles local signing, and `plans/` holds the original project plan.

## Build, Test, and Development Commands

- `make build` builds a release executable, assembles `build/vindustilpasser.app`, and signs it.
- `make build-unsigned` ad-hoc signs the same app without a Keychain identity; Accessibility access may need renewal.
- `open build/vindustilpasser.app` runs the local app; grant Accessibility access when prompted.
- `make test` compiles and runs Swift Testing logic tests (macOS 14 or later).
- `make setup-signing` creates a persistent local code-signing identity in the login Keychain.
- `make clean` removes build outputs but preserves signing state; `make build-dmg` creates an ad-hoc signed app in an unnotarized distributable DMG.

Use macOS 13 or later and Xcode Command Line Tools. Consult `README.md` before deploying with `make deploy`.

## Coding Style & Naming Conventions

Follow nearby Swift code: four-space indentation, UpperCamelCase types and files, lowerCamelCase properties and methods, and focused types grouped by feature directory. Prefer small, explicit AppKit and Accessibility helpers over new abstractions. The package uses Swift 5 language mode. No formatter or linter is configured; keep formatting consistent with adjacent files and check `git diff --check`.

## Testing Guidelines

Add focused `@Test` cases with `#expect` in a matching `*Tests.swift` file for logic changes. There is no stated coverage threshold.

## Verification

```sh
make test
codesign --verify --strict build/vindustilpasser.app
hdiutil verify "build/vindustilpasser-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist).dmg"
```

Build both artifacts first. Manually check window control and Accessibility access on left/right and stacked displays, alternate Dock positions, size-constrained apps, and keyboard-layout changes. Describe manual checks in the pull request.

## Commit & Pull Request Guidelines

The Git history has only the initial `Init plan for vindustilpasser` commit, so no established commit convention exists. Use short, imperative subjects that name the affected behavior. Pull requests should explain the change, note test results and manual verification, link relevant issues, and include screenshots for visible UI changes.

## Signing & Local State

Do not commit `build/`, `.build/`, or `.local-signing/`. Keep the bundle ID and signing identity stable: changing either can invalidate macOS Accessibility authorization. Settings are stored outside the repository at `~/.config/vindustilpasser/settings.json`.

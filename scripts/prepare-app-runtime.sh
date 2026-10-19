#!/bin/sh
set -eu

app="$1"
plist="$app/Contents/Info.plist"
minimum_version=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")
executable_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")
executable="$app/Contents/MacOS/$executable_name"
binary_versions=$(xcrun vtool -show-build "$executable" | awk '$1 == "minos" { print $2 }')

if [ -z "$binary_versions" ]; then
    echo 'ERROR: could not read the executable deployment target.' >&2
    exit 1
fi
for version in $binary_versions; do
    if [ "$version" != "$minimum_version" ]; then
        echo "ERROR: executable requires macOS $version, but the app declares macOS $minimum_version." >&2
        exit 1
    fi
done

mkdir -p "$app/Contents/Frameworks"
xcrun swift-stdlib-tool --copy --scan-executable "$executable" --platform macosx \
    --destination "$app/Contents/Frameworks"
for library in "$app/Contents/Frameworks/"*.dylib; do
    if [ -f "$library" ]; then
        codesign --force --sign - "$library"
    fi
done

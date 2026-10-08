#!/bin/sh
set -eu

plist=${PLIST_PATH:-Resources/Info.plist}

valid_version() {
    case "$1" in
        ''|*[!0-9.]*) return 1 ;;
    esac
    printf '%s\n' "$1" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
}

case "${1:-}" in
    set)
        version=${VERSION:-}
        ;;
    patch|minor|major)
        current=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
        if ! valid_version "$current"; then
            printf 'Invalid current version: %s\n' "$current" >&2
            exit 1
        fi

        major=${current%%.*}
        remainder=${current#*.}
        minor=${remainder%%.*}
        patch=${remainder#*.}

        case "$1" in
            patch) version="$major.$minor.$(expr "$patch" + 1)" ;;
            minor) version="$major.$(expr "$minor" + 1).0" ;;
            major) version="$(expr "$major" + 1).0.0" ;;
        esac
        ;;
    *)
        printf 'Usage: %s {set|patch|minor|major}\n' "$0" >&2
        exit 1
        ;;
esac

if ! valid_version "$version"; then
    printf 'Invalid version: %s (expected N.N.N)\n' "$version" >&2
    exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
printf 'Updated %s to version %s\n' "$plist" "$version"

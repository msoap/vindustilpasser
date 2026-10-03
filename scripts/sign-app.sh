#!/bin/sh
set -eu
app="$1"
bundle_id="$2"
identity='vindustilpasser Local Development'
if security find-identity -v -p codesigning | grep -Fq '"'"$identity"'"'; then
    codesign --force --sign "$identity" --timestamp=none -i "$bundle_id" \
        --keychain "$HOME/Library/Keychains/login.keychain-db" "$app"
    echo "Signing mode: local identity ($identity)"
    mkdir -p .local-signing
    requirement="$(codesign -d -r- "$app" 2>&1 | sed -n 's/^#* *designated => //p')"
    if [ -z "$requirement" ]; then
        echo 'ERROR: could not read the designated requirement from the signed app' >&2
        exit 1
    fi
    if [ -f .local-signing/designated-requirement.txt ] && [ "$(cat .local-signing/designated-requirement.txt)" != "$requirement" ]; then
        echo 'WARNING: designated requirement changed; Accessibility authorization may need renewal'
    fi
    printf '%s\n' "$requirement" > .local-signing/designated-requirement.txt
else
    if [ -f .local-signing/designated-requirement.txt ]; then
        echo 'ERROR: the persistent local signing identity is unavailable; refusing to switch to ad-hoc signing.' >&2
        echo 'Unlock or repair the login Keychain, then rebuild.' >&2
        exit 1
    fi
    codesign --force --sign - -i "$bundle_id" "$app"
    echo 'Signing mode: ad-hoc'
    echo 'WARNING: Accessibility permission may need to be granted again after a rebuild.'
    echo 'Create the "vindustilpasser Local Development" self-signed Code Signing identity in Keychain for stable local identity.'
fi
codesign --verify --strict --verbose=2 "$app"

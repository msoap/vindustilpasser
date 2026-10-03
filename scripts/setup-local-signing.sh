#!/bin/sh
set -eu

identity='vindustilpasser Local Development'
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -Fq '"'"$identity"'"'; then
    echo "Existing valid Code Signing identity: $identity"
    exit 0
fi

if security find-certificate -c "$identity" "$keychain" >/dev/null 2>&1; then
    echo "ERROR: a certificate named $identity exists but is not a valid Code Signing identity." >&2
    echo 'Repair it in Keychain Access before creating another identity with the same name.' >&2
    exit 1
fi

umask 077
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/vindustilpasser-signing.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

openssl req -new -newkey rsa:3072 -nodes -x509 -days 3650 \
    -subj "/CN=$identity" \
    -addext 'basicConstraints=critical,CA:TRUE' \
    -addext 'keyUsage=critical,digitalSignature,keyCertSign' \
    -addext 'extendedKeyUsage=codeSigning' \
    -keyout "$temporary_directory/private-key.pem" \
    -out "$temporary_directory/certificate.pem" >/dev/null 2>&1

openssl rand -hex 24 > "$temporary_directory/passphrase"
openssl pkcs12 -export \
    -legacy -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -inkey "$temporary_directory/private-key.pem" \
    -in "$temporary_directory/certificate.pem" \
    -out "$temporary_directory/identity.p12" \
    -passout "file:$temporary_directory/passphrase"

security import "$temporary_directory/identity.p12" -k "$keychain" \
    -P "$(cat "$temporary_directory/passphrase")" -T /usr/bin/codesign
security add-trusted-cert -p codeSign -r trustRoot -k "$keychain" "$temporary_directory/certificate.pem"

if ! security find-identity -v -p codesigning | grep -Fq '"'"$identity"'"'; then
    echo 'ERROR: the new certificate is not a valid Code Signing identity.' >&2
    exit 1
fi

echo "Created persistent local Code Signing identity: $identity"

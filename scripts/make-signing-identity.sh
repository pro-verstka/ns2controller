#!/bin/bash
set -euo pipefail
NAME="ns2controller"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
    echo "Identity '$NAME' already exists"
    exit 0
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 -nodes \
    -subj "/CN=$NAME" -addext "extendedKeyUsage=codeSigning" -addext "keyUsage=digitalSignature" -addext "basicConstraints=CA:FALSE" 2>/dev/null
openssl pkcs12 -export -out "$TMP/identity.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout pass:tmp -name "$NAME" -legacy 2>/dev/null \
    || openssl pkcs12 -export -out "$TMP/identity.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout pass:tmp -name "$NAME"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P tmp -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"
echo "Identity '$NAME' created; scripts/build-app.sh will use it automatically."

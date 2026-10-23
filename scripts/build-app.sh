#!/bin/bash
# macOS ties the Accessibility / Screen Recording grants to the signing identity: an ad-hoc signature changes on
# every build and would drop them, so we sign with a stable self-signed identity kept in a project-local keychain.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="Proper Bar Local Signing"
KEYCHAIN="$PWD/.signing/properbar.keychain-db"
KEYCHAIN_PASSWORD="properbar"

if [ ! -f "$KEYCHAIN" ]; then
    mkdir -p .signing
    work=$(mktemp -d)
    cat > "$work/cert.cnf" <<EOF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$IDENTITY
[ext]
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
basicConstraints=critical,CA:false
EOF
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$work/key.pem" -out "$work/cert.pem" -days 3650 -config "$work/cert.cnf" 2>/dev/null
    openssl pkcs12 -export -legacy -inkey "$work/key.pem" -in "$work/cert.pem" -out "$work/id.p12" -passout pass:x 2>/dev/null \
        || openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -out "$work/id.p12" -passout pass:x
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security import "$work/id.p12" -k "$KEYCHAIN" -P x -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
    rm -rf "$work"
fi

source scripts/env.sh

swift build -c release

APP="build/ProperBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ProperBar "$APP/Contents/MacOS/ProperBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" "$APP"

mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/ProperBar.app"
cp -R "$APP" "$HOME/Applications/ProperBar.app"
echo "Installed $HOME/Applications/ProperBar.app"

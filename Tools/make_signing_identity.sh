#!/bin/bash
# Create the self-signed code signing identity "NRIME Code Signing" in the login
# keychain. Does nothing if it already exists.
#
# Why: macOS (TCC) remembers an ad-hoc signed app by its binary hash, so every
#      NRIME update silently lost its Accessibility / post-event grant while
#      System Settings still showed it as allowed. Signing every build with the
#      same certificate makes TCC remember "com.nrime.inputmethod.app signed by
#      this certificate" instead, and the grant survives updates.
# - The certificate is not marked as trusted; signing does not need that. It
#   identifies the app, it does not make Gatekeeper trust it.
# - Valid for 20 years. If the keychain loses it, run this again and grant the
#   permission once more.
# - The private key lives only in the keychain; temporary files are deleted.
# Same approach as cssgsg's tools/mac/make-signing-identity.sh.
set -euo pipefail
NAME="NRIME Code Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -qF "\"$NAME\""; then
    echo "Already exists: $NAME"
    security find-identity -p codesigning "$KEYCHAIN" | grep -F "\"$NAME\""
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF
PASS="$(openssl rand -hex 16)"
openssl req -x509 -newkey rsa:2048 -sha256 -days 7300 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
# macOS `security` only reads the legacy PKCS12 algorithms.
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
    -out "$TMP/identity.p12" -passout "pass:$PASS"
# -T: codesign may use this key without asking.
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
echo "Created:"
security find-identity -p codesigning "$KEYCHAIN" | grep -F "\"$NAME\""

#!/bin/bash
# Build + relaunch kbf for local development.
# Signs with a stable self-signed identity ("kbf Local Signing") when present so
# the Accessibility grant persists across rebuilds; falls back to ad-hoc otherwise.
#
# To create the identity once (so rebuilds stop dropping the grant):
#   openssl req -x509 -newkey rsa:2048 -keyout k.pem -out c.pem -days 3650 -nodes \
#     -subj "/CN=kbf Local Signing" -addext "extendedKeyUsage=codeSigning" -addext "basicConstraints=critical,CA:false"
#   openssl pkcs12 -export -inkey k.pem -in c.pem -out kbf.p12 -passout pass:kbfpass \
#     -name "kbf Local Signing" -legacy -macalg sha1
#   security import kbf.p12 -k ~/Library/Keychains/login.keychain-db -P kbfpass -T /usr/bin/codesign -A
set -e
cd "$(dirname "$0")"

IDENT="kbf Local Signing"
if security find-certificate -c "$IDENT" >/dev/null 2>&1; then
  SIGN="CODE_SIGN_IDENTITY=$IDENT"
else
  SIGN="CODE_SIGN_IDENTITY=-"
fi

xcodebuild -project kbf.xcodeproj -scheme kbf -configuration Debug "$SIGN" build 2>&1 | tail -1
APP=$(find ~/Library/Developer/Xcode/DerivedData/kbf-*/Build/Products/Debug -maxdepth 1 -name 'kbf.app' | head -1)
pkill -f "kbf.app/Contents/MacOS/kbf" 2>/dev/null || true
sleep 0.5
open "$APP"
echo "launched: $APP"

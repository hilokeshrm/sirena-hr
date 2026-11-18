#!/usr/bin/env bash
# Builds the Sirena HR iPhone app. Run on a Mac, from anywhere:  app/ios/build.sh
#
# Signing must be set up once in Xcode first (open ios/Runner.xcworkspace, pick your Team under
# Signing & Capabilities). See README.md in this folder.
#
# Override the server when it changes:
#   API_BASE=https://new.address/api SERVER_CERT_SHA256=<fingerprint> app/ios/build.sh
set -euo pipefail

API_BASE="${API_BASE:-https://106.51.70.71:7777/api}"
# SHA-256 of the server's certificate. The app trusts that one certificate and no other.
SERVER_CERT_SHA256="${SERVER_CERT_SHA256:-46DF38B3F495D7FBF04042CC80ECE4DA58A7AE2C61CAC659A1E475BB92499306}"

cd "$(dirname "$0")/.."
echo "Server:      $API_BASE"
echo "Certificate: ${SERVER_CERT_SHA256:0:16}…"

flutter pub get
(cd ios && pod install)
flutter build ipa --release \
  --dart-define=API_BASE="$API_BASE" \
  --dart-define=SERVER_CERT_SHA256="$SERVER_CERT_SHA256"

echo
echo "Done. Upload build/ios/ipa/*.ipa with Transporter, or:"
echo "  xcrun altool --upload-app -f build/ios/ipa/*.ipa -t ios -u <your-apple-id>"

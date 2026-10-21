#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Upload the exported IPA to App Store Connect (TestFlight). The API key stays outside the repo:
#   ASC_KEY_ID, ASC_ISSUER_ID, and ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8
: "${ASC_KEY_ID:?set ASC_KEY_ID (see docs/setup/apple.md)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (see docs/setup/apple.md)}"
ipa=$(ls apple/build/release/*.ipa)
xcrun altool --upload-app --type ios --file "$ipa" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

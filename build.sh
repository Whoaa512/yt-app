#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SYMROOT="$REPO_ROOT/build"

cd "$REPO_ROOT/YTApp"

xcodebuild -scheme YTApp -configuration Debug \
    SYMROOT="$SYMROOT" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build

# TODO: When Apple Development cert is available, re-sign with entitlements:
#   codesign --force --sign "Apple Development" \
#     --entitlements "$REPO_ROOT/YTApp/YTApp/YTApp.entitlements" \
#     "$SYMROOT/Debug/YTApp.app"
# This enables com.apple.developer.web-browser for passkey/WebAuthn support.

#!/bin/zsh
# Checks that the app's Swift code compiles, without Xcode.
# It uses the Mac Catalyst (iPad-on-Mac) libraries that come with the
# Command Line Tools, so it catches most mistakes before you build on an iPad.
#
#   zsh Tools/typecheck.sh
set -euo pipefail

ROOT="${0:A:h:h}"
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
IOS_SUPPORT="$SDK/System/iOSSupport"

if [[ ! -d "$IOS_SUPPORT" ]]; then
  echo "This Mac's SDK has no iOSSupport folder. Install the Command Line Tools: xcode-select --install"
  exit 1
fi

cd "$ROOT"
swiftc -typecheck -swift-version 5 -sdk "$SDK" -target "$ARCH-apple-ios17.0-macabi" \
  -Fsystem "$IOS_SUPPORT/System/Library/Frameworks" -I "$IOS_SUPPORT/usr/lib/swift" \
  $(find Parchment -name '*.swift')
echo "✓ All Swift files type-check."

#!/bin/bash
# Build Logi : nu-type and install it to ~/Applications.  Usage: ./build.sh [--no-install]
set -euo pipefail
cd "$(dirname "$0")"

# SwiftUI macros (@State) need full Xcode, not just the Command Line Tools.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi
swift build -c release
APP="build/Logi nu-type.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -f .build/release/LogiNuType "$APP/Contents/MacOS/LogiNuType"
cp -f Support/Info.plist "$APP/Contents/Info.plist"
cp -f Support/Resources/mouse-cutaway.png "$APP/Contents/Resources/"
cp -f Support/AppIcon.icns "$APP/Contents/Resources/"

# Sign with a stable identity when one exists, so macOS keeps the Accessibility /
# Input Monitoring permissions across rebuilds. Override with SIGN_IDENTITY=...
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' 'NR==1 && /"/ {print $2}')}"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Signed with: ${IDENTITY:-ad-hoc}"

if [[ "${1:-}" != "--no-install" ]]; then
  pkill -x LogiLite 2>/dev/null || true   # pre-rename builds
  pkill -x LogiNuType 2>/dev/null && sleep 1 || true
  mkdir -p "$HOME/Applications"
  ditto "$APP" "$HOME/Applications/Logi nu-type.app"
  open "$HOME/Applications/Logi nu-type.app"
  echo "Installed to ~/Applications/Logi nu-type.app"
fi

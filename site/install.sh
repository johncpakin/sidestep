#!/bin/sh
# Sidestep installer · https://sidestep.sh
# Downloads the latest release of Sidestep.app into /Applications.
# Read this whole file first if you like; it's short on purpose.
set -e

REPO="johncpakin/sidestep"
APP="/Applications/Sidestep.app"

echo "Fetching the latest Sidestep release..."
URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
  | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | cut -d'"' -f4)

if [ -z "$URL" ]; then
  echo "No packaged release yet. Build from source instead (needs Xcode CLT):"
  echo "  git clone https://github.com/$REPO"
  echo "  cd sidestep && ./scripts/build-app.sh --install"
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "$URL" -o "$TMP/sidestep.zip"
ditto -xk "$TMP/sidestep.zip" "$TMP"
[ -d "$TMP/Sidestep.app" ] || { echo "Unexpected archive layout; aborting."; exit 1; }

rm -rf "$APP"
ditto "$TMP/Sidestep.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "✓ Sidestep is in /Applications. Opening..."
open "$APP"

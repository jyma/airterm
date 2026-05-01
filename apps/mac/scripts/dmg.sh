#!/bin/bash
# Wrap an already-built AirTerm.app into a distributable .dmg.
#
# Run `bash apps/mac/scripts/bundle.sh --release` first so the .app
# is universal + properly signed; this script only does the DMG layout.
#
# Output: apps/mac/build/AirTerm-<version>.dmg
#
# Tooling: pure-stdlib hdiutil — no `create-dmg` or other npm helpers,
# so the script runs the same on a CI runner as on the developer box.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAC_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$MAC_DIR/build/AirTerm.app"
VERSION="0.1.0"
OUT_DIR="$MAC_DIR/build"
OUT_DMG="$OUT_DIR/AirTerm-$VERSION.dmg"
STAGE="$OUT_DIR/dmg-stage"

if [ ! -d "$APP_DIR" ]; then
  echo "AirTerm.app not found at $APP_DIR" >&2
  echo "Run: bash $SCRIPT_DIR/bundle.sh --release" >&2
  exit 1
fi

echo "Staging DMG contents..."
rm -rf "$STAGE"
mkdir -p "$STAGE"

# Copy the .app, preserving symlinks + extended attributes (codesign needs them).
ditto "$APP_DIR" "$STAGE/AirTerm.app"

# A symlink named "Applications" is the standard "drag me here" target —
# users see /Applications without having to type the path.
ln -s /Applications "$STAGE/Applications"

# (Optional) ship a README so first-launch users know what to do.
cat > "$STAGE/README.txt" << 'README'
AirTerm — terminal that takes over from any browser.

Install
  Drag AirTerm into Applications, then double-click to launch.
  First run: macOS will ask you to grant Accessibility (so AirTerm
  can capture global key chords) and Screen Recording (for tab
  thumbnails — optional, can be skipped). Both live in:
  System Settings → Privacy & Security.

Pair a phone
  AirTerm → File → Pair New Device…
  Scan the QR with your phone's browser.

Source / issues
  https://github.com/jyma/airterm
README

# Throw away any stale DMG from a prior build so hdiutil doesn't
# complain about an existing target.
rm -f "$OUT_DMG"

echo "Building DMG..."
# UDBZ = bzip2-compressed read-only — small + universally readable.
# `-fs HFS+` for compatibility with macOS 14 host's hdiutil defaults
# without losing extended attributes; the .app's signature survives.
hdiutil create \
  -volname "AirTerm $VERSION" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDBZ \
  -ov \
  "$OUT_DMG" >/dev/null

# Sanity check: read back and verify the DMG image is well-formed.
hdiutil verify "$OUT_DMG" >/dev/null

# Clean up the staging dir so subsequent re-runs don't accumulate cruft.
rm -rf "$STAGE"

SIZE=$(du -h "$OUT_DMG" | awk '{ print $1 }')
echo ""
echo "✅ DMG ready: $OUT_DMG ($SIZE)"
echo ""
echo "Distribute by attaching it to a GitHub release, or:"
echo "  open $OUT_DMG    # mount + verify the drag-to-Applications layout"

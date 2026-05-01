#!/bin/bash
# Build and create AirTerm.app bundle for proper macOS permission management.
#
# Default mode is `--debug`: fast iteration build, host-arch airprompt,
# unsigned (only ad-hoc signed so TCC recognizes the bundle).
#
# `--release` mode produces a shippable artifact:
#   • Swift target built in release configuration (-O, smaller binary).
#   • airprompt lipo'd into a universal x86_64 + arm64 binary so the
#     same .app runs on Apple Silicon and Intel Macs.
#   • Bundle still ad-hoc signed; real Developer-ID signing + notarization
#     is the user's responsibility (see release-sign.sh in a later slice).
set -e

MODE="debug"
for arg in "$@"; do
  case "$arg" in
    --release) MODE="release" ;;
    --debug)   MODE="debug" ;;
    -h|--help)
      echo "Usage: bundle.sh [--debug|--release]"
      echo "  --debug    (default) host-arch airprompt, swift -c debug"
      echo "  --release  universal airprompt (x86_64 + arm64), swift -c release"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAC_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$(dirname "$MAC_DIR")")"
APP_NAME="AirTerm"
BUNDLE_ID="com.airterm.app"
APP_DIR="$MAC_DIR/build/${APP_NAME}.app"
AIRPROMPT_DIR="$REPO_ROOT/tools/airprompt"

cd "$MAC_DIR"

echo "Building Swift target ($MODE)..."
swift build -c "$MODE"

# airprompt is the Rust-side companion that renders the shell prompt. We
# bundle it inside Resources/bin/ so the Mac app can hand its absolute path
# to PTY-spawned shells without depending on a system-wide install.
echo "Building airprompt (Rust, $MODE)..."
if [ "$MODE" = "release" ]; then
  # Universal: build both targets, then `lipo` them together so a single
  # .app works on every supported Mac. rustup must already have the
  # targets installed (`rustup target add aarch64-apple-darwin
  # x86_64-apple-darwin`); we add them defensively here so a cold CI
  # runner doesn't fail on the first build.
  (cd "$AIRPROMPT_DIR" && rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null 2>&1 || true)
  (cd "$AIRPROMPT_DIR" && cargo build --release --quiet --target=aarch64-apple-darwin)
  (cd "$AIRPROMPT_DIR" && cargo build --release --quiet --target=x86_64-apple-darwin)
  AIRPROMPT_BIN="$AIRPROMPT_DIR/target/airprompt-universal"
  lipo -create \
    "$AIRPROMPT_DIR/target/aarch64-apple-darwin/release/airprompt" \
    "$AIRPROMPT_DIR/target/x86_64-apple-darwin/release/airprompt" \
    -output "$AIRPROMPT_BIN"
else
  (cd "$AIRPROMPT_DIR" && cargo build --release --quiet)
  AIRPROMPT_BIN="$AIRPROMPT_DIR/target/release/airprompt"
fi

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary (path differs between debug/release SwiftPM layouts).
cp ".build/$MODE/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>AirTerm</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>AirTerm uses AppleEvents for optional integrations.</string>
</dict>
</plist>
PLIST

# Ship airprompt inside the bundle (Resources/bin/airprompt).
mkdir -p "$APP_DIR/Contents/Resources/bin"
cp "$AIRPROMPT_BIN" "$APP_DIR/Contents/Resources/bin/airprompt"
codesign --force --sign - "$APP_DIR/Contents/Resources/bin/airprompt"

# Ship the prompt presets so users can `cp <preset> ~/.config/airterm/prompt.toml`.
mkdir -p "$APP_DIR/Contents/Resources/airprompt-presets"
cp "$AIRPROMPT_DIR/presets/"*.toml "$APP_DIR/Contents/Resources/airprompt-presets/"
cp "$AIRPROMPT_DIR/presets/README.md" "$APP_DIR/Contents/Resources/airprompt-presets/"

# Ad-hoc sign so TCC recognizes it stably
codesign --force --sign - "$APP_DIR"

# Copy terminal resources (SwiftPM-emitted .bundle)
cp -r ".build/$MODE/AirTerm_AirTerm.bundle" "$APP_DIR/Contents/Resources/" 2>/dev/null || true

echo ""
echo "✅ Built ($MODE): $APP_DIR"
echo ""
if [ "$MODE" = "release" ]; then
  echo "  airprompt arch: $(lipo -archs "$APP_DIR/Contents/Resources/bin/airprompt")"
fi
echo ""
echo "Run with:  open $APP_DIR"
echo ""
if [ "$MODE" = "release" ]; then
  echo "Next: bash apps/mac/scripts/dmg.sh   to package as a DMG."
else
  echo "After first run, add AirTerm to:"
  echo "  System Settings → Privacy & Security → Accessibility"
  echo "  System Settings → Privacy & Security → Screen Recording"
fi

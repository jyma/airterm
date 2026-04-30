#!/bin/bash
# Build and create AirTerm.app bundle for proper macOS permission management
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAC_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$(dirname "$MAC_DIR")")"
APP_NAME="AirTerm"
BUNDLE_ID="com.airterm.app"
APP_DIR="$MAC_DIR/build/${APP_NAME}.app"
AIRPROMPT_DIR="$REPO_ROOT/tools/airprompt"

cd "$MAC_DIR"

echo "Building Swift target..."
swift build -c debug

# airprompt is the Rust-side companion that renders the shell prompt. We
# bundle it inside Resources/bin/ so the Mac app can hand its absolute path
# to PTY-spawned shells without depending on a system-wide install.
echo "Building airprompt (Rust)..."
(cd "$AIRPROMPT_DIR" && cargo build --release --quiet)

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp ".build/debug/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

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
cp "$AIRPROMPT_DIR/target/release/airprompt" "$APP_DIR/Contents/Resources/bin/airprompt"
codesign --force --sign - "$APP_DIR/Contents/Resources/bin/airprompt"

# Ad-hoc sign so TCC recognizes it stably
codesign --force --sign - "$APP_DIR"

echo ""
echo "✅ Built: $APP_DIR"
echo ""
echo "Run with:  open $APP_DIR"
echo ""
echo "After first run, add AirTerm to:"
echo "  System Settings → Privacy & Security → Accessibility"
echo "  System Settings → Privacy & Security → Screen Recording"

# Copy terminal resources
cp -r ".build/debug/AirTerm_AirTerm.bundle" "$APP_DIR/Contents/Resources/" 2>/dev/null || true

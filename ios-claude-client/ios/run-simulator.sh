#!/bin/bash
# Build ClaudeRemote for iOS Simulator, launch it, and take screenshots.
#
# Prerequisites: Xcode installed from App Store
#   https://apps.apple.com/app/xcode/id497799835
#
# After Xcode install, run once:
#   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
#   sudo xcodebuild -runFirstLaunch
#
# Usage:
#   ./run-simulator.sh            # build, launch, take screenshots
#   ./run-simulator.sh screenshot  # screenshot only (app already running)

set -euo pipefail
cd "$(dirname "$0")"

PROJECT="ClaudeRemote.xcodeproj"
SCHEME="ClaudeRemote"
SIM_NAME="${SIM_NAME:-iPhone 16 Pro}"
SCREENSHOT_DIR="./screenshots"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# ── Check Xcode ───────────────────────────────────────────────────
if ! xcodebuild -version &>/dev/null; then
    echo "Xcode not found. Install from App Store:"
    echo "  https://apps.apple.com/app/xcode/id497799835"
    echo ""
    echo "After install, run:"
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    echo "  sudo xcodebuild -runFirstLaunch"
    exit 1
fi

# ── Generate project if needed ────────────────────────────────────
if [ ! -d "$PROJECT" ]; then
    info "Generating Xcode project..."
    python3 gen-xcode.py
fi

# ── Check if scheme exists (project opened in Xcode at least once) ─
if ! xcodebuild -project "$PROJECT" -list 2>/dev/null | grep -q "$SCHEME"; then
    warn "Scheme not found. Opening project in Xcode to auto-create scheme..."
    open "$PROJECT"
    echo ""
    echo "Waiting for Xcode to create scheme (this may take 30s)..."
    echo "After Xcode opens, you can close it and re-run this script."
    echo ""
    echo "Or wait — I'll check every 5 seconds..."
    for i in $(seq 1 12); do
        sleep 5
        if xcodebuild -project "$PROJECT" -list 2>/dev/null | grep -q "$SCHEME"; then
            info "Scheme ready!"
            break
        fi
        echo "  waiting... ($((i*5))s)"
    done
fi

# ── Build for simulator ───────────────────────────────────────────
info "Building for iOS Simulator ($SIM_NAME)..."

xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -destination "platform=iOS Simulator,name=$SIM_NAME" \
    -configuration Debug \
    -derivedDataPath ./DerivedData \
    -quiet \
    2>&1 | grep -E "(error:|warning:|BUILD|^\\*\\*)" || true

BUILD_EXIT=${PIPESTATUS[0]}
if [ $BUILD_EXIT -ne 0 ]; then
    echo ""
    echo "Build failed. Try opening in Xcode first: open $PROJECT"
    echo "Then Product → Build (Cmd+B) to see detailed errors."
    exit $BUILD_EXIT
fi

info "Build successful"

# ── Find .app ─────────────────────────────────────────────────────
APP_PATH=$(find ./DerivedData/Build/Products/Debug-iphonesimulator -name "ClaudeRemote.app" -type d | head -1)
if [ -z "$APP_PATH" ]; then
    echo "Could not find ClaudeRemote.app in build products"
    echo "Search path: ./DerivedData/Build/Products/"
    find ./DerivedData -name "*.app" -type d 2>/dev/null
    exit 1
fi
info "App: $APP_PATH"

# ── Boot simulator if needed ──────────────────────────────────────
BOOTED=$(xcrun simctl list devices | grep "$SIM_NAME" | grep "Booted" || true)
if [ -z "$BOOTED" ]; then
    info "Booting $SIM_NAME..."
    # Find or create the simulator
    SIM_UDID=$(xcrun simctl list devices | grep "$SIM_NAME" | head -1 | grep -oE '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}')
    if [ -z "$SIM_UDID" ]; then
        # Create the simulator
        RUNTIME=$(xcrun simctl list runtimes | grep "iOS" | tail -1 | grep -oE 'com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]+')
        SIM_UDID=$(xcrun simctl create "$SIM_NAME" "iPhone 16 Pro" "$RUNTIME")
        info "Created simulator: $SIM_UDID"
    fi
    xcrun simctl boot "$SIM_UDID"
    info "Waiting for simulator to boot..."
    xcrun simctl bootstatus "$SIM_UDID" -b 2>/dev/null || sleep 15
fi

SIM_UDID=$(xcrun simctl list devices | grep "$SIM_NAME" | grep "Booted" | head -1 | grep -oE '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}')
info "Simulator booted: $SIM_UDID"

# ── Install app ───────────────────────────────────────────────────
info "Installing app..."
xcrun simctl install "$SIM_UDID" "$APP_PATH"

# ── Launch app ────────────────────────────────────────────────────
info "Launching ClaudeRemote..."
BUNDLE_ID="com.deejay.clauderemote"
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"

info "Waiting for app to render..."
sleep 5

# ── Take screenshots ──────────────────────────────────────────────
mkdir -p "$SCREENSHOT_DIR"

info "Taking screenshots..."

# Screenshot 1: Terminal view (main screen)
xcrun simctl io "$SIM_UDID" screenshot "$SCREENSHOT_DIR/01-terminal.png"
info "  Screenshot 1: $SCREENSHOT_DIR/01-terminal.png"

# Open simulator window so user can see it
open -a Simulator

# Screenshot 2: After typing something (simulated)
xcrun simctl io "$SIM_UDID" screenshot "$SCREENSHOT_DIR/02-terminal-active.png"
info "  Screenshot 2: $SCREENSHOT_DIR/02-terminal-active.png"

echo ""
info "=============================================="
info "  Screenshots saved to $SCREENSHOT_DIR/"
info "  Simulator is running — you can interact with it"
info "=============================================="
echo ""
echo "To take more screenshots:"
echo "  ./run-simulator.sh screenshot"
echo ""
echo "To kill simulator:"
echo "  xcrun simctl shutdown all"
echo ""
ls -la "$SCREENSHOT_DIR/"

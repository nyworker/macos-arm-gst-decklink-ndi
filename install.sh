#!/usr/bin/env bash
set -euo pipefail

BINARY_DEST="/usr/local/bin/gst-decklink-ndi"
CONFIG_DIR="/etc/gst-decklink-ndi"
LOG_DIR="/var/log/gst-decklink-ndi"
PLIST_DEST="$HOME/Library/LaunchAgents/com.gst-decklink-ndi.plist"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ── 1. Homebrew ────────────────────────────────────────────────────────────────
if [[ ! -x /opt/homebrew/bin/brew ]]; then
    error "Homebrew not found at /opt/homebrew/bin/brew."
    error "Install from: https://brew.sh"
    exit 1
fi
info "Homebrew found ✓"

# ── 2. GStreamer ───────────────────────────────────────────────────────────────
info "Installing / updating GStreamer via Homebrew (idempotent)…"
brew install gstreamer

# ── 3. Spot-check required GStreamer elements ──────────────────────────────────
GST_INSPECT="/opt/homebrew/bin/gst-inspect-1.0"
REQUIRED_ELEMENTS=(decklinkvideosrc decklinkaudiosrc ndisink ndisinkcombiner ccextractor)
ALL_GOOD=true
for elem in "${REQUIRED_ELEMENTS[@]}"; do
    if "$GST_INSPECT" "$elem" &>/dev/null; then
        info "  GStreamer element '$elem' ✓"
    else
        error "  GStreamer element '$elem' NOT FOUND"
        ALL_GOOD=false
    fi
done
if [[ "$ALL_GOOD" != "true" ]]; then
    error "One or more required GStreamer elements are missing."
    error "Check your GStreamer installation: brew reinstall gstreamer"
    exit 1
fi

# ── 4. NDI SDK ────────────────────────────────────────────────────────────────
NDI_LIB="/Library/NDI SDK for Apple/lib/macOS/libndi_newtek.dylib"
if [[ -f "$NDI_LIB" ]]; then
    info "NDI SDK found ✓"
else
    warn "NDI SDK (libndi_newtek.dylib) not found."
    warn "Download 'NDI SDK for Apple' from: https://ndi.video/for-developers/ndi-sdk/"
    warn "Run the .pkg installer, then re-run this script."
    warn "(Continuing — the tool will warn again at runtime.)"
fi

# ── 5. Blackmagic Desktop Video ───────────────────────────────────────────────
BM_PATH="/Library/Application Support/Blackmagic Design"
if [[ -d "$BM_PATH" ]]; then
    info "Blackmagic Desktop Video found ✓"
else
    warn "Blackmagic Desktop Video does not appear to be installed."
    warn "Download from: https://www.blackmagicdesign.com/support/family/capture-and-playback"
    warn "(Continuing — the tool will warn again at runtime.)"
fi

# ── 6. Build ──────────────────────────────────────────────────────────────────
info "Building release binary…"
swift build -c release
info "Build succeeded ✓"

# ── 7. Install binary ─────────────────────────────────────────────────────────
info "Installing binary to $BINARY_DEST …"
sudo install -m 755 .build/release/gst-decklink-ndi "$BINARY_DEST"

# ── 8. Install config ─────────────────────────────────────────────────────────
sudo mkdir -p "$CONFIG_DIR"
if [[ ! -f "$CONFIG_DIR/config.json" ]]; then
    sudo cp config.json "$CONFIG_DIR/config.json"
    info "Default config installed at $CONFIG_DIR/config.json"
else
    info "Config already exists at $CONFIG_DIR/config.json (not overwritten)"
fi

# ── 9. Log directory ──────────────────────────────────────────────────────────
sudo mkdir -p "$LOG_DIR"
sudo chown "$(whoami)" "$LOG_DIR"
info "Log directory ready: $LOG_DIR"

# ── 10. launchd instructions ──────────────────────────────────────────────────
echo ""
info "Installation complete."
echo ""
echo "  To run interactively:"
echo "    gst-decklink-ndi --verbose --ndi-name \"Studio A\""
echo ""
echo "  To install as a LaunchAgent (starts on login, auto-restarts):"
echo "    cp com.gst-decklink-ndi.plist $PLIST_DEST"
echo "    launchctl load $PLIST_DEST"
echo ""
echo "  Or simply run:"
echo "    make load"
echo ""

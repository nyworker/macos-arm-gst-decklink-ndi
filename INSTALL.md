# Installation Guide — gst-decklink-ndi on macOS ARM

Complete step-by-step instructions for a fresh Apple Silicon (arm64) Mac running macOS 13+.

---

## Prerequisites Overview

| Component | Required | Install Method |
|-----------|----------|----------------|
| Xcode Command Line Tools | Yes | `xcode-select --install` |
| Homebrew | Yes | Script from brew.sh |
| GStreamer 1.20+ | Yes | `brew install gstreamer` |
| NDI SDK for Apple | Yes | .pkg from ndi.video |
| Blackmagic Desktop Video | Yes | .pkg from blackmagicdesign.com |

---

## Step 1 — Xcode Command Line Tools

```bash
xcode-select --install
```

A dialog will appear. Click **Install**. This installs Swift, clang, and the developer tools.

**Verify:**
```bash
swift --version
# Expected: swift-driver version: ... Swift version 5.9+ (swiftlang-...)
```

**Common error:** `xcode-select: error: command line tools are already installed`
→ Already done, continue.

---

## Step 2 — Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After install, follow the on-screen instructions to add Homebrew to your PATH. For Apple Silicon:

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

**Verify:**
```bash
brew --version
# Expected: Homebrew 4.x.x
which brew
# Expected: /opt/homebrew/bin/brew
```

---

## Step 3 — GStreamer (via Homebrew)

This single formula installs GStreamer 1.28+ along with all required plugins:
`libgstdecklink`, `libgstndi`, `libgstclosedcaption`, `libgstrsclosedcaption`.

```bash
brew install gstreamer
```

This may take several minutes as it downloads a large monorepo bundle.

**Verify:**
```bash
gst-launch-1.0 --version
# Expected: gst-launch version 1.28.x

gst-inspect-1.0 decklinkvideosrc | head -5
gst-inspect-1.0 ndisink | head -5
gst-inspect-1.0 ccextractor | head -5
```

**Common error:** `gst-inspect-1.0: command not found`
→ Run `eval "$(/opt/homebrew/bin/brew shellenv)"` then retry, or open a new terminal.

---

## Step 4 — NDI SDK for Apple

1. Go to: **https://ndi.video/for-developers/ndi-sdk/**
2. Download **NDI SDK for Apple** (select the macOS/Apple Silicon package)
3. Run the `.pkg` installer
4. Accept the license agreement

**Verify:**
```bash
ls "/Library/NDI SDK for Apple/lib/macOS/libndi_newtek.dylib"
# Expected: the file exists (no "No such file" error)
```

**If missing:** The GStreamer NDI plugin (`libgstndi.dylib`) loads `libndi_newtek.dylib` at runtime.
Without it, `ndisink` will fail when the pipeline starts, not at element inspection time.

---

## Step 5 — Blackmagic Desktop Video

1. Go to: **https://www.blackmagicdesign.com/support/family/capture-and-playback**
2. Find your DeckLink card model and download **Desktop Video** for macOS
3. Run the `.pkg` installer
4. **Restart your Mac** if prompted (kernel extension / driver installation)

**Verify:**
```bash
ls "/Library/Application Support/Blackmagic Design"
# Expected: directory exists

/Applications/Blackmagic\ Desktop\ Video/Blackmagic\ Desktop\ Video\ Setup.app/Contents/MacOS/Blackmagic\ Desktop\ Video\ Setup &
# Expected: Desktop Video Setup app opens, shows your DeckLink device
```

**Common error:** DeckLink device not detected
→ Ensure the card is seated, the Mac has restarted post-install, and the correct Desktop Video version is installed for your card.

---

## Step 6 — Build the Tool

```bash
cd /path/to/gst-decklink-ndi
swift build -c release
```

**Verify:**
```bash
.build/release/gst-decklink-ndi --version
# Expected: 1.0.0

.build/release/gst-decklink-ndi --help
# Expected: usage summary with all flags
```

---

## Step 7 — Install System-Wide

```bash
sudo make install
```

This:
- Copies binary to `/usr/local/bin/gst-decklink-ndi`
- Creates `/etc/gst-decklink-ndi/config.json` (if not present)
- Creates `/var/log/gst-decklink-ndi/` with your user as owner

**Verify:**
```bash
which gst-decklink-ndi
# Expected: /usr/local/bin/gst-decklink-ndi

gst-decklink-ndi --version
# Expected: 1.0.0
```

---

## Step 8 — Configure

Edit the config to match your setup:

```bash
sudo nano /etc/gst-decklink-ndi/config.json
```

Key fields:

| Field | Default | Description |
|-------|---------|-------------|
| `device_number` | 0 | DeckLink device index (0-based) |
| `video_mode` | `"auto"` | `"auto"`, `"1080p30"`, `"1080i60"`, `"720p60"`, etc. |
| `audio_channels` | 2 | 2, 8, or 16 |
| `ndi_name` | `"DeckLink NDI"` | Name visible in NDI discovery |
| `enable_audio` | true | Include audio in NDI stream |
| `enable_cc` | true | Extract CEA-608/708 closed captions |
| `log_level` | `"info"` | `"error"`, `"warning"`, `"info"`, `"debug"`, `"trace"` |
| `restart_delay_seconds` | 2.0 | Wait time before auto-restart |
| `max_restart_attempts` | 0 | 0 = restart forever |

To list available DeckLink modes:
```bash
gst-inspect-1.0 decklinkvideosrc | grep -A2 "mode:"
```

---

## Step 9 — Run Interactively

```bash
gst-decklink-ndi --verbose --ndi-name "Studio A"
```

**Expected output:**
```
[INFO]  gst-launch-1.0 version 1.28.x ✓
[INFO]  GStreamer element 'decklinkvideosrc' ✓
[INFO]  NDI SDK found at /Library/NDI SDK for Apple/lib/macOS/libndi_newtek.dylib ✓
[INFO]  Starting NDI stream 'Studio A' from DeckLink device 0…
[INFO]  Launching: /opt/homebrew/bin/gst-launch-1.0 -e ndisinkcombiner …
```

On another machine on the same LAN, open **NDI Tools Studio Monitor** and look for "Studio A".

**Dry-run (no hardware needed):**
```bash
gst-decklink-ndi --dry-run
gst-decklink-ndi --dry-run --no-audio --no-cc
```

Press **Ctrl+C** to stop.

---

## Step 10 — Run as a Service (launchd)

Install and start the LaunchAgent (runs at login, auto-restarts on crash):

```bash
make load
```

**Verify:**
```bash
launchctl list | grep gst-decklink-ndi
# Expected: <PID>  0  com.gst-decklink-ndi

make logs
# Tails /var/log/gst-decklink-ndi/stdout.log and stderr.log
```

**Stop the service:**
```bash
make unload
```

**Remove everything:**
```bash
make unload
sudo make uninstall
```

---

## Troubleshooting

### "No such element: decklinkvideosrc"
- Blackmagic Desktop Video not installed, or GStreamer DeckLink plugin not found.
- Run: `ls /opt/homebrew/lib/gstreamer-1.0/libgstdecklink.dylib`
- If missing: `brew reinstall gstreamer`

### "No such element: ndisink"
- NDI SDK not installed, or libgstndi can't find libndi_newtek.dylib.
- Verify: `ls "/Library/NDI SDK for Apple/lib/macOS/libndi_newtek.dylib"`

### Pipeline restarts immediately with exit code 1
- Set `--verbose` and check stderr for GStreamer error messages.
- Common causes: DeckLink not connected, wrong device-number, wrong video mode.
- Try: `gst-decklink-ndi --verbose --mode auto --device 0`

### NDI stream not visible on network
- Confirm NDI SDK is installed and the library is loadable.
- Check firewall: NDI uses UDP multicast and TCP (ports 5960+).
- Verify the NDI name matches what you're looking for in Studio Monitor.

### Service won't start (launchd)
- Check: `cat /var/log/gst-decklink-ndi/stderr.log`
- LaunchAgents require a logged-in user session (DeckLink is a user-space driver).
- Ensure `/usr/local/bin/gst-decklink-ndi` is executable: `ls -la /usr/local/bin/gst-decklink-ndi`

---

## Playing a File to DeckLink Output

To play a local MPEG-TS file (e.g. 1080i 29.97 H.264 + AC-3) to a DeckLink output device:

```bash
gst-launch-1.0 -e \
  filesrc location="/path/to/file.ts" \
  ! tsdemux name=d \
  d. ! queue ! h264parse ! avdec_h264 ! videoconvert \
      ! video/x-raw,format=UYVY \
      ! decklinkvideosink device-number=0 mode=1080i5994 \
  d. ! queue ! ac3parse ! avdec_ac3 ! audioconvert \
      ! audio/x-raw,format=S16LE,rate=48000,channels=2 \
      ! decklinkaudiosink device-number=0
```

Adjust `mode=` to match your content:

| Content | mode string |
|---------|-------------|
| 1080i 29.97 | `1080i5994` |
| 1080i 25 | `1080i50` |
| 1080i 30 | `1080i60` |
| 1080p 29.97 | `1080p2997` |
| 1080p 25 | `1080p25` |
| 720p 59.94 | `720p5994` |

Press **Ctrl+C** to stop. Use `gst-inspect-1.0 decklinkvideosink` to list all available modes.

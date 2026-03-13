# macos-arm-gst-decklink-ndi

macOS ARM Swift CLI that captures DeckLink video + audio and streams it as NDI using GStreamer.

> Companion to [gst-decklink-ndi](https://github.com/nyworker/gst-decklink-ndi) (Linux). Same concept, native macOS implementation.

---

## Features

- **Video + Audio + Closed Captions** (CEA-608/708 via `output-cc=true`)
- **Auto-restart** on pipeline failure with configurable delay and attempt limit
- **Graceful shutdown** on SIGTERM/SIGINT with SIGKILL fallback
- **Dependency validation** at startup — checks GStreamer elements, NDI SDK, Blackmagic Desktop Video
- **JSON config file** + CLI flag overrides
- **launchd LaunchAgent** for unattended service operation
- **Dry-run mode** to preview the pipeline command without running it

---

## Requirements

| Component | Version | Install |
|-----------|---------|---------|
| macOS | 13+ (arm64) | — |
| Swift | 5.9+ | `xcode-select --install` |
| GStreamer | 1.20+ | `brew install gstreamer` |
| NDI SDK for Apple | any | [ndi.video](https://ndi.video/for-developers/ndi-sdk/) |
| Blackmagic Desktop Video | any | [blackmagicdesign.com](https://www.blackmagicdesign.com/support/family/capture-and-playback) |

See [INSTALL.md](INSTALL.md) for full step-by-step setup on a fresh machine.

---

## Quick Start

```bash
# Build
swift build -c release

# Dry-run — preview the GStreamer pipeline without running it
.build/release/gst-decklink-ndi --dry-run --ndi-name "Studio A"

# Run
.build/release/gst-decklink-ndi --ndi-name "Studio A" --verbose
```

The NDI source will appear in NDI Tools Studio Monitor on the same LAN.

---

## Pipeline Modes

| Flags | Pipeline |
|-------|----------|
| *(default)* | Video + Audio + CC (CEA-608/708) |
| `--no-cc` | Video + Audio |
| `--no-audio --no-cc` | Video only |
| `--scte35` | Video + Audio + CC + VANC (SCTE best-effort, see note) |

> **SCTE-35 note:** `output-vanc=true` extracts VANC data as GstMeta, but GStreamer has no SCTE-104 parser or SCTE-35 converter. SCTE cues will not reach the NDI stream without a custom plugin.

---

## CLI Reference

```
USAGE: gst-decklink-ndi [options]

OPTIONS:
  --device <n>            DeckLink device number (default: 0)
  --mode <mode>           Video mode: auto, 1080p30, 1080i60, 720p60, … (default: auto)
  --ndi-name <name>       NDI stream name (default: "DeckLink NDI")
  -c, --config <path>     JSON config file
  --no-audio              Disable audio capture
  --no-cc                 Disable closed-caption extraction
  --scte35                Enable SCTE-35 best-effort (logs limitation notice)
  --restart-delay <s>     Seconds between restarts (default: 2.0)
  --max-restarts <n>      Max restart attempts, 0 = unlimited (default: 0)
  -v, --verbose           Echo log messages to stderr
  --dry-run               Print pipeline command and exit
```

---

## Config File

Copy and edit `config.json`:

```json
{
  "device_number": 0,
  "video_mode": "auto",
  "audio_channels": 2,
  "ndi_name": "DeckLink NDI",
  "enable_audio": true,
  "enable_cc": true,
  "restart_delay_seconds": 2.0,
  "max_restart_attempts": 0,
  "gst_launch_path": "/opt/homebrew/bin/gst-launch-1.0",
  "log_level": "info"
}
```

CLI flags override config file values.

---

## Install as a Service

```bash
sudo make install   # install binary + config + log dir
make load           # install launchd agent, start on login
make logs           # tail /var/log/gst-decklink-ndi/
make unload         # stop service
```

---

## GStreamer Pipelines (reference)

### Video + Audio + CC
```
gst-launch-1.0 -e \
  ndisinkcombiner name=combiner ! ndisink ndi-name="NAME" sync=false \
  decklinkvideosrc device-number=0 mode=auto output-cc=true \
    ! queue max-size-buffers=2 leaky=downstream ! combiner.video \
  decklinkaudiosrc device-number=0 \
    ! queue max-size-buffers=2 leaky=downstream \
    ! audioconvert ! audio/x-raw,format=F32LE,rate=48000,channels=2 \
    ! combiner.audio
```

### Video Only
```
gst-launch-1.0 -e \
  decklinkvideosrc device-number=0 mode=auto \
  ! queue max-size-buffers=2 leaky=downstream \
  ! ndisink ndi-name="NAME" sync=false
```

---

## License

MIT

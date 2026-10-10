# AudioBridge

Stream your Linux PC's system audio to your phone (iOS or Android) over USB. No app required — just a web browser.

## What is this?

Plug your phone into your Linux PC, open a webpage, and your phone becomes a wireless speaker. Audio is captured from PulseAudio/PipeWire and sent over a local WebSocket connection through USB tethering.

Works with Arch, Fedora, Ubuntu, Debian, openSUSE, and most other distros.

## Requirements

- Linux with PulseAudio or PipeWire
- Python 3.10+
- `parec` and `pactl` (usually comes with `pulseaudio-utils` or `pipewire-pulse`)
- `openssl`
- An iOS or Android device + USB cable

## Install

```
git clone https://github.com/gamer871/audiobridge.git
cd audiobridge
chmod +x install.sh
./install.sh
```

The installer handles dependencies, sets up a systemd service, configures your firewall, adds Android/iOS udev rules, and generates TLS certificates.

## Mobile Setup (first time only)

The Web Audio API requires HTTPS, so you need to trust the generated certificate once:

### Android
1. Enable **USB Tethering** on your Android device.
2. Open Chrome and navigate to `https://<hostname>.local:8000` (or your PC's IP).
3. Accept the self-signed certificate warning ("Advanced -> Proceed").

### iPhone (iOS)
1. Enable **Personal Hotspot** (or USB Tethering) on your iPhone.
2. Open Safari and navigate to `https://<hostname>.local:8000/ca.crt` (or your PC's IP) to download the CA cert. Bypass the warning to download it.
3. **Settings → General → VPN & Device Management** → select the downloaded profile and install it.
4. **Settings → General → About → Certificate Trust Settings** → enable full trust for "AudioBridge CA".

## Usage

1. Plug in your phone and enable USB Tethering / Personal Hotspot.
2. Open `https://<hostname>.local:8000` in Safari or Chrome.
3. Hit play.

The service runs in the background and auto-starts when your phone is plugged in.

### Features

- **Ultra-low latency** — tightly optimized for USB tethering speeds
- **Background playback** — keeps playing even when the phone screen is locked
- **Wireless mic** — use your phone as a PC microphone (shows up as `Mobile_Microphone` in Discord, OBS, etc.)
- **Auto-reconnect** — handles cable disconnects or iOS/Android interruptions gracefully
- **Volume boost** — up to 200%
- **Advanced tuning** — adjust target UI latency and hardware buffer size for older devices

### Service commands

```
systemctl --user start audiobridge
systemctl --user stop audiobridge
systemctl --user restart audiobridge
journalctl --user -u audiobridge -f
```

### CLI flags

| Flag | Default | Description |
|---|---|---|
| `-p, --port` | 8000 | Server port |
| `-r, --rate` | 48000 | Sample rate (Hz) |
| `-c, --channels` | 2 | Channel count |
| `-l, --latency` | 10 | Capture latency (ms) |
| `-d, --device` | auto | PulseAudio source |
| `--cert-dir` | `~/.config/audiobridge/certs` | Cert directory |

## Uninstall

```
./uninstall.sh
```

## License

MIT

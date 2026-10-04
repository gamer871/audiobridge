# AudioBridge

Stream your Linux PC's system audio to your iPhone over USB. No app required — just Safari.

## What is this?

Plug your iPhone into your Linux PC, open a webpage, and your phone becomes a wireless speaker. Audio is captured from PulseAudio/PipeWire and sent over a local WebSocket connection through USB tethering.

Works with Arch, Fedora, Ubuntu, Debian, openSUSE, and most other distros.

## Requirements

- Linux with PulseAudio or PipeWire
- Python 3.10+
- `parec` and `pactl` (usually comes with `pulseaudio-utils` or `pipewire-pulse`)
- `openssl`
- An iPhone + USB cable

## Install

```
git clone https://github.com/gamer871/audiobridge.git
cd audiobridge
chmod +x install.sh
./install.sh
```

The installer handles dependencies, sets up a systemd service, configures your firewall, and generates TLS certificates.

## iPhone Setup (first time only)

iOS requires HTTPS, so you need to trust a certificate once:

1. Enable **Personal Hotspot** on your iPhone and plug it in via USB.
2. Open Safari → `http://<your-pc-ip>:8080` to download the CA cert.
3. **Settings → General → VPN & Device Management** → install the profile.
4. **Settings → General → About → Certificate Trust Settings** → enable trust.

## Usage

1. Plug in your iPhone and enable Personal Hotspot.
2. Open `https://<hostname>.local:8000` in Safari.
3. Hit play.

The service runs in the background and auto-starts when your phone is plugged in.

### Features

- **Background playback** — keeps playing with the screen locked
- **Music / Video mode** — Video mode compresses dynamic range so dialogue is audible over explosions
- **Wireless mic** — use your iPhone as a PC microphone (shows up as `iPhone_Microphone` in Discord, OBS, etc.)
- **Auto-reconnect** — handles cable disconnects gracefully
- **Volume boost** — up to 200%

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

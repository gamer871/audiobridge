# AudioBridge

Stream your Linux PC's system audio to your iPhone over a wired USB connection. No apps to install on your phone — just open Safari.

## How it works

AudioBridge captures your system's audio output using PulseAudio/PipeWire and streams it as low-latency raw PCM over a secure WebSocket. Your iPhone connects via USB tethering (Personal Hotspot), creating a fast private wired network. You open a webpage in Safari that receives the audio and plays it through your phone's speakers.

**Key features:**
- Wired connection via USB — no Wi-Fi needed
- No iOS app required — runs entirely in Safari
- Low latency (~40-80ms)
- Auto-starts when you plug in your phone
- Auto-reconnects if the cable is unplugged and reconnected
- Works with PulseAudio and PipeWire
- Supports Arch, Fedora, Ubuntu, Debian, openSUSE, and more

## Requirements

- Linux with PulseAudio or PipeWire (with `pipewire-pulse`)
- Python 3.10+
- `parec` (from `pulseaudio-utils` or `pipewire-pulse`)
- `openssl`
- An iPhone with a USB cable

## Install

```bash
git clone https://github.com/gamer871/audiobridge.git
cd audiobridge
chmod +x install.sh
./install.sh
```

The installer will:
- Install system dependencies for your distro
- Create a Python virtual environment with the `websockets` package
- Set up a systemd user service
- Configure a udev rule to auto-start when an iPhone is connected
- Open firewall ports (8000, 8080)
- Generate TLS certificates

## First-time iPhone setup

Since iOS requires HTTPS, you need to install a one-time certificate on your iPhone:

1. **Enable Personal Hotspot** on your iPhone and plug it into your PC via USB.

2. **Download the certificate.** Open Safari on your iPhone and go to:
   ```
   http://<your-pc-ip>:8080
   ```
   This will prompt you to download a certificate profile. Tap **Allow**.

3. **Install the profile.** Go to **Settings → General → VPN & Device Management**, tap the "AudioBridge CA" profile, and tap **Install**.

4. **Trust the certificate.** Go to **Settings → General → About → Certificate Trust Settings** and enable full trust for **AudioBridge CA**.

You only need to do this once.

## Usage

After installation, AudioBridge runs as a background service.

1. Plug your iPhone into your PC via USB.
2. Enable **Personal Hotspot** on your iPhone.
3. Open Safari and go to `https://<your-pc-hostname>.local:8000`
4. Tap the play button.

### Features & Controls

| Feature | Description |
|---|---|
| **Two-way Wireless Mic** | Tap "Enable iPhone Mic" to stream your phone's microphone back to your PC. It automatically appears as `iPhone_Microphone` in Discord/OBS/Sound Settings. |
| **Smart Audio Mode** | Toggle between **Music** (unaltered, high fidelity) and **Video** (boosted dialogue, dynamic range compression for loud explosions). |
| **Background Playback** | Lock your screen or switch apps on your iPhone — the audio will continue playing seamlessly via native iOS media integration. |
| **Auto-Reconnect** | Automatically reconnects and resumes playing if you unplug and re-plug your USB cable. |

*Note: Latency and buffer settings are hardcoded to the optimal values for wired USB (100ms max latency, 1024 frames) to ensure a perfectly smooth, zero-configuration experience.*

### Commands

```bash
# Start / stop / restart
systemctl --user start audiobridge
systemctl --user stop audiobridge
systemctl --user restart audiobridge

# Check status
systemctl --user status audiobridge

# View logs
journalctl --user -u audiobridge -f
```

### CLI options

```bash
# Run manually with custom settings
~/.local/share/audiobridge/venv/bin/python3 ~/.local/share/audiobridge/server.py \
  --port 8000 \
  --rate 48000 \
  --channels 2 \
  --latency 20
```

| Flag | Default | Description |
|---|---|---|
| `-p, --port` | `8000` | Server port |
| `-r, --rate` | `48000` | Sample rate (Hz) |
| `-c, --channels` | `2` | Audio channels |
| `-l, --latency` | `20` | Capture latency (ms) |
| `-d, --device` | auto | PulseAudio monitor source |
| `--cert-dir` | `~/.config/audiobridge/certs` | TLS certificate directory |

## Uninstall

```bash
./uninstall.sh
```

Removes the service, virtual microphones, udev rule, application files, and certificates.

## License

MIT

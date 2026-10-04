#!/usr/bin/env python3
"""
AudioBridge Server — Stream system audio to any device over your local network.

Captures the default PulseAudio/PipeWire output monitor and serves it as raw
PCM over a secure WebSocket. Also serves the web client over HTTPS on the
same port.
"""

import asyncio
import argparse
import os
import ssl
import subprocess
import sys

try:
    import websockets
    from websockets.http11 import Response
    from websockets.datastructures import Headers
except ImportError:
    print("Error: 'websockets' package not found.")
    print("Install it with: pip install websockets")
    sys.exit(1)


# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DEFAULT_PORT = 8000
DEFAULT_SAMPLE_RATE = 48000
DEFAULT_CHANNELS = 2
DEFAULT_LATENCY_MS = 10
DEFAULT_CHUNK_FRAMES = 480  # 10ms at 48kHz

WEB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "web")


# ---------------------------------------------------------------------------
# Audio helpers
# ---------------------------------------------------------------------------

def get_default_monitor() -> str:
    """Return the PulseAudio/PipeWire monitor source for the default sink."""
    try:
        result = subprocess.run(
            ["pactl", "get-default-sink"],
            capture_output=True, text=True, check=True,
        )
        sink = result.stdout.strip()
        if sink:
            return f"{sink}.monitor"
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass

    # Fallback: try to find any monitor source
    try:
        result = subprocess.run(
            ["pactl", "list", "sources", "short"],
            capture_output=True, text=True, check=True,
        )
        for line in result.stdout.splitlines():
            parts = line.split("\t")
            if len(parts) >= 2 and ".monitor" in parts[1]:
                return parts[1]
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass

    print("Error: Could not detect a PulseAudio/PipeWire monitor source.")
    print("Make sure PulseAudio or PipeWire (with pipewire-pulse) is running.")
    sys.exit(1)


# ---------------------------------------------------------------------------
# Certificate management
# ---------------------------------------------------------------------------

def ensure_certs(cert_dir: str) -> tuple[str, str]:
    """Generate self-signed TLS certificates if they don't exist."""
    cert_path = os.path.join(cert_dir, "cert.pem")
    key_path = os.path.join(cert_dir, "key.pem")
    ca_cert_pem = os.path.join(cert_dir, "ca-cert.pem")
    ca_key_path = os.path.join(cert_dir, "ca-key.pem")
    ca_cert_der = os.path.join(cert_dir, "ca-cert.crt")

    if os.path.exists(cert_path) and os.path.exists(key_path):
        return cert_path, key_path

    os.makedirs(cert_dir, exist_ok=True)
    print("Generating TLS certificates...")

    # Generate CA
    subprocess.run([
        "openssl", "genrsa", "-out", ca_key_path, "2048"
    ], check=True, capture_output=True)
    subprocess.run([
        "openssl", "req", "-new", "-x509",
        "-key", ca_key_path, "-out", ca_cert_pem,
        "-days", "825", "-subj", "/CN=AudioBridge CA"
    ], check=True, capture_output=True)

    # Generate server key + CSR
    subprocess.run([
        "openssl", "genrsa", "-out", key_path, "2048"
    ], check=True, capture_output=True)
    subprocess.run([
        "openssl", "req", "-new",
        "-key", key_path, "-out", os.path.join(cert_dir, "server.csr"),
        "-subj", "/CN=AudioBridge"
    ], check=True, capture_output=True)

    # Determine SANs — include common private IP ranges and hostname
    hostname = subprocess.run(
        ["hostname"], capture_output=True, text=True
    ).stdout.strip()

    san_entries = [f"DNS:{hostname}.local", "DNS:localhost"]

    # Find all local IPs
    try:
        result = subprocess.run(
            ["hostname", "-I"], capture_output=True, text=True
        )
        for ip in result.stdout.strip().split():
            if ":" not in ip:  # Skip IPv6
                san_entries.append(f"IP:{ip}")
    except FileNotFoundError:
        pass

    san_entries.append("IP:127.0.0.1")

    ext_file = os.path.join(cert_dir, "ext.cnf")
    with open(ext_file, "w") as f:
        f.write("authorityKeyIdentifier=keyid,issuer\n")
        f.write("basicConstraints=CA:FALSE\n")
        f.write("keyUsage=digitalSignature,keyEncipherment\n")
        f.write("extendedKeyUsage=serverAuth\n")
        f.write(f"subjectAltName={','.join(san_entries)}\n")

    subprocess.run([
        "openssl", "x509", "-req",
        "-in", os.path.join(cert_dir, "server.csr"),
        "-CA", ca_cert_pem, "-CAkey", ca_key_path, "-CAcreateserial",
        "-out", cert_path, "-days", "825", "-sha256",
        "-extfile", ext_file
    ], check=True, capture_output=True)

    # DER format for iOS install
    subprocess.run([
        "openssl", "x509", "-in", ca_cert_pem,
        "-outform", "DER", "-out", ca_cert_der
    ], check=True, capture_output=True)

    print(f"Certificates generated in {cert_dir}")
    print(f"CA certificate for iOS: {ca_cert_der}")
    return cert_path, key_path


# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

class AudioBridgeServer:
    def __init__(self, port, sample_rate, channels, latency_ms, monitor, cert_dir):
        self.port = port
        self.sample_rate = sample_rate
        self.channels = channels
        self.latency_ms = latency_ms
        self.monitor = monitor
        self.clients = set()
        self.chunk_bytes = (
            int(sample_rate * latency_ms / 1000) * channels * 2
        )

        cert_path, key_path = ensure_certs(cert_dir)
        self.ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.ssl_ctx.load_cert_chain(cert_path, key_path)

    def process_request(self, connection, request):
        if request.path == "/":
            return self._serve_file("index.html", "text/html; charset=utf-8")
        elif request.path == "/ws":
            return None  # Upgrade to WebSocket
        else:
            body = b"Not Found"
            return Response(404, "Not Found",
                            Headers([("Content-Length", str(len(body)))]), body)

    def _serve_file(self, filename, content_type):
        filepath = os.path.join(WEB_DIR, filename)
        try:
            with open(filepath, "rb") as f:
                body = f.read()
            return Response(200, "OK", Headers([
                ("Content-Type", content_type),
                ("Content-Length", str(len(body))),
                ("Cache-Control", "no-cache"),
            ]), body)
        except FileNotFoundError:
            body = b"File not found"
            return Response(404, "Not Found",
                            Headers([("Content-Length", str(len(body)))]), body)

    async def ws_handler(self, websocket):
        self.clients.add(websocket)
        remote = websocket.remote_address
        print(f"[+] Client connected from {remote[0]}:{remote[1]}  "
              f"(total: {len(self.clients)})")
        try:
            async for message in websocket:
                if isinstance(message, bytes) and hasattr(self, 'mic_proc') and self.mic_proc and self.mic_proc.returncode is None:
                    self.mic_proc.stdin.write(message)
                    await self.mic_proc.stdin.drain()
        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            self.clients.discard(websocket)
            print(f"[-] Client disconnected  (total: {len(self.clients)})")

    async def audio_capture(self):
        print(f"Starting audio capture: {self.monitor}")
        print(f"  Sample rate: {self.sample_rate} Hz")
        print(f"  Channels:    {self.channels}")
        print(f"  Latency:     {self.latency_ms} ms")
        print(f"  Chunk size:  {self.chunk_bytes} bytes")

        proc = await asyncio.create_subprocess_exec(
            "parec",
            f"--format=s16le",
            f"--channels={self.channels}",
            f"--rate={self.sample_rate}",
            f"--device={self.monitor}",
            "--raw",
            f"--latency-msec={self.latency_ms}",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )

        try:
            while True:
                data = await proc.stdout.readexactly(self.chunk_bytes)
                if self.clients:
                    websockets.broadcast(self.clients, data)
        except (asyncio.CancelledError, asyncio.IncompleteReadError):
            pass
        finally:
            proc.terminate()

    async def setup_mic(self):
        print("Setting up virtual microphone (AudioBridge_Mic)...")
        cmd = ["pactl", "load-module", "module-null-sink", 
               "media.class=Audio/Source/Virtual", 
               "sink_name=AudioBridge_Mic", 
               "sink_properties=device.description=AudioBridge_Mic"]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True)
            if res.returncode == 0:
                self.mic_module_id = res.stdout.strip()
                print(f"Virtual microphone created (Module ID: {self.mic_module_id})")
            else:
                print("Warning: Failed to create virtual microphone.", res.stderr)
        except Exception as e:
            print(f"Warning: {e}")

        self.mic_proc = await asyncio.create_subprocess_exec(
            "pacat", "--playback", "--device=AudioBridge_Mic", 
            "--format=s16le", "--rate=48000", "--channels=1", "--latency-msec=10",
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )

    def cleanup_mic(self):
        if hasattr(self, 'mic_proc') and self.mic_proc and self.mic_proc.returncode is None:
            self.mic_proc.terminate()
        if hasattr(self, 'mic_module_id') and self.mic_module_id:
            subprocess.run(["pactl", "unload-module", self.mic_module_id])

    async def run(self):
        print(f"\n  AudioBridge")
        print(f"  ──────────────────────────────")
        print(f"  URL:  https://localhost:{self.port}")
        print(f"  ──────────────────────────────\n")
        
        await self.setup_mic()

        try:
            async with websockets.serve(
                self.ws_handler,
                "0.0.0.0",
                self.port,
                ssl=self.ssl_ctx,
                process_request=self.process_request,
                ping_interval=None,
                max_size=None,
            ):
                await self.audio_capture()
        finally:
            self.cleanup_mic()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="AudioBridge — Stream system audio to your phone",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "-p", "--port", type=int, default=DEFAULT_PORT,
        help=f"Server port (default: {DEFAULT_PORT})",
    )
    parser.add_argument(
        "-r", "--rate", type=int, default=DEFAULT_SAMPLE_RATE,
        help=f"Sample rate in Hz (default: {DEFAULT_SAMPLE_RATE})",
    )
    parser.add_argument(
        "-c", "--channels", type=int, default=DEFAULT_CHANNELS,
        help=f"Audio channels (default: {DEFAULT_CHANNELS})",
    )
    parser.add_argument(
        "-l", "--latency", type=int, default=DEFAULT_LATENCY_MS,
        help=f"Capture latency in ms (default: {DEFAULT_LATENCY_MS})",
    )
    parser.add_argument(
        "-d", "--device",
        help="PulseAudio monitor source (auto-detected if not specified)",
    )
    parser.add_argument(
        "--cert-dir",
        default=os.path.join(
            os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")),
            "audiobridge", "certs"
        ),
        help="Directory for TLS certificates",
    )
    args = parser.parse_args()

    monitor = args.device or get_default_monitor()

    server = AudioBridgeServer(
        port=args.port,
        sample_rate=args.rate,
        channels=args.channels,
        latency_ms=args.latency,
        monitor=monitor,
        cert_dir=args.cert_dir,
    )

    try:
        asyncio.run(server.run())
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()

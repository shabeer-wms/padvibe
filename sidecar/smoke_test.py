"""Smoke test for the sidecar, used locally and by CI on every OS.

Usage:
    python sidecar/smoke_test.py                      # runs midi_server.py from source
    python sidecar/smoke_test.py path/to/midi_server  # runs a frozen build

Checks: port binds, ping/pong, device listing, and (if an output device exists)
playback start + natural finish. Exits non-zero on the first failure.
"""
import asyncio
import json
import math
import os
import queue
import struct
import subprocess
import sys
import tempfile
import threading
import time
import wave

import websockets

BIND_TIMEOUT = float(os.environ.get("SMOKE_BIND_TIMEOUT", "90"))  # first run of a new bundle is slow on macOS


def make_wav(path, seconds=0.3, rate=44100):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(
            struct.pack("<h", int(8000 * math.sin(2 * math.pi * 440 * i / rate)))
            for i in range(int(seconds * rate))
        ))


def start_server(cmd):
    env = dict(os.environ, PADVIBE_PARENT_PID=str(os.getpid()), PYTHONUNBUFFERED="1")
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
    lines = queue.Queue()
    threading.Thread(
        target=lambda: [lines.put(line.rstrip()) for line in proc.stdout], daemon=True
    ).start()
    start = time.time()
    while time.time() - start < BIND_TIMEOUT:
        try:
            line = lines.get(timeout=0.5)
        except queue.Empty:
            if proc.poll() is not None:
                raise SystemExit(f"FAIL: sidecar exited early with code {proc.returncode}")
            continue
        print(f"  sidecar: {line}")
        if line.startswith("PORT_BIND_SUCCESS:"):
            return proc, int(line.split(":")[1]), time.time() - start
    proc.kill()
    raise SystemExit(f"FAIL: no PORT_BIND_SUCCESS within {BIND_TIMEOUT}s")


async def recv_type(ws, wanted, timeout=10):
    """Waits for a message of the wanted type, ignoring the 20Hz level stream."""
    end = time.time() + timeout
    while time.time() < end:
        msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=end - time.time()))
        if msg.get("type") == wanted:
            return msg
        if msg.get("type") == "error" and wanted != "error":
            raise SystemExit(f"FAIL: sidecar error while waiting for {wanted}: {msg}")
    raise SystemExit(f"FAIL: timed out waiting for {wanted}")


async def exercise(port):
    async with websockets.connect(f"ws://127.0.0.1:{port}") as ws:
        await ws.send(json.dumps({"command": "ping"}))
        await recv_type(ws, "pong")
        print("  ok: ping/pong")

        await ws.send(json.dumps({"command": "list_devices"}))
        await recv_type(ws, "device_list")
        print("  ok: midi device list")

        await ws.send(json.dumps({"command": "list_audio_devices"}))
        devices = (await recv_type(ws, "audio_device_list"))["devices"]
        print(f"  ok: {len(devices)} audio output device(s)")
        if not devices:
            print("  skip: playback (no output device on this machine)")
        else:
            with tempfile.TemporaryDirectory() as tmp:
                wav = os.path.join(tmp, "tone.wav")
                make_wav(wav)
                await ws.send(json.dumps({"command": "play_audio", "file_path": wav}))
                started = await recv_type(ws, "audio_started")
                await recv_type(ws, "audio_finished", timeout=10)
                print(f"  ok: playback started and finished ({started['duration_seconds']:.2f}s clip)")

                # A waveform request decodes once and shares it with playback; unload frees it.
                await ws.send(json.dumps({"command": "get_waveform", "file_path": wav, "points": 20}))
                wave_msg = await recv_type(ws, "waveform_data")
                assert len(wave_msg["data"]) == 20, "waveform should have 20 points"
                print("  ok: waveform")
                await ws.send(json.dumps({"command": "unload_audio", "file_path": wav}))
                await recv_type(ws, "audio_unloaded")
                print("  ok: unload")

        await ws.send(json.dumps({"command": "shutdown"}))


def main():
    cmd = [sys.argv[1]] if len(sys.argv) > 1 else [sys.executable, os.path.join(os.path.dirname(__file__), "midi_server.py")]
    print(f"Starting: {' '.join(cmd)}")
    proc, port, bind_seconds = start_server(cmd)
    print(f"  bound on {port} after {bind_seconds:.1f}s")
    try:
        asyncio.run(exercise(port))
        proc.wait(timeout=10)
    finally:
        if proc.poll() is None:
            proc.kill()
    print("PASS")


if __name__ == "__main__":
    main()

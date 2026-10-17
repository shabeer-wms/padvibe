import asyncio
import errno as errno_mod
import json
import websockets
import sys
import threading
import os
import sidecar_log
from sidecar_log import log

sidecar_log.setup()

from audio_engine import AudioEngine
from midi_engine import MidiEngine

# Global Engines
audio_engine = AudioEngine()
midi_engine = None # Initialized in main

# Clients
clients = set()

# High-rate commands (fader moves) go to the log file only, not stdout.
QUIET_COMMANDS = {"set_volume", "set_master_volume", "set_routing", "set_filter"}


def cleanup():
    """Performs cleanup of engines before exiting."""
    log.info("Cleanup: stopping MIDI and audio engines")
    try:
        if midi_engine:
            midi_engine.stop()
        audio_engine.stop_all()
    except Exception:
        log.exception("Cleanup failed")

def _pid_alive(pid):
    """Cross-platform liveness check. os.kill(pid, 0) is unsafe on Windows
    (it terminates the target), so use the Win32 API there."""
    if sys.platform == "win32":
        import ctypes
        PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
        STILL_ACTIVE = 259
        kernel32 = ctypes.windll.kernel32
        handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
        if not handle:
            return False
        try:
            code = ctypes.c_ulong()
            if not kernel32.GetExitCodeProcess(handle, ctypes.byref(code)):
                return False
            return code.value == STILL_ACTIVE
        finally:
            kernel32.CloseHandle(handle)
    try:
        os.kill(pid, 0)
    except PermissionError:
        return True
    except OSError:
        return False
    return True

def watchdog():
    """Exits when the Flutter app dies. The app passes its pid in
    PADVIBE_PARENT_PID because os.getppid() is the PyInstaller bootloader
    (which outlives a force-killed app), not the app itself."""
    import time
    try:
        parent_pid = int(os.environ.get("PADVIBE_PARENT_PID", ""))
    except ValueError:
        parent_pid = os.getppid()
    log.info("Watchdog watching parent pid %s", parent_pid)
    while True:
        if not _pid_alive(parent_pid):
            log.warning("Parent process %s is gone; exiting", parent_pid)
            cleanup()
            os._exit(0)
        time.sleep(2)

def summarize(data):
    """A log-safe copy of a command: long strings are truncated."""
    out = {}
    for key, value in data.items():
        if isinstance(value, str) and len(value) > 200:
            value = value[:200] + f"...({len(value)} chars)"
        elif isinstance(value, (list, dict)) and len(str(value)) > 200:
            value = f"<{type(value).__name__} len={len(value)}>"
        out[key] = value
    return out

async def send_json(websocket, payload):
    """Sends a message to one client, logging its type."""
    msg_type = payload.get("type")
    log.info("-> %s%s", msg_type, _detail(payload))
    await websocket.send(json.dumps(payload))

def _detail(payload):
    keys = [k for k in ("stream_id", "message", "file_path", "duration_seconds") if k in payload]
    for k in ("devices", "data"):
        if k in payload and isinstance(payload[k], list):
            keys.append(f"{k}[{len(payload[k])}]")
    parts = [f"{k}={payload[k]}" if k in payload else k for k in keys]
    return (" " + " ".join(str(p)[:160] for p in parts)) if parts else ""

async def broadcast(message):
    """Sends a message to all connected WebSocket clients."""
    if not clients:
        return
    # Snapshot the set so concurrent disconnects don't corrupt the zip below.
    snapshot = list(clients)
    tasks = [client.send(message) for client in snapshot]
    results = await asyncio.gather(*tasks, return_exceptions=True)

    to_remove = set()
    for client, result in zip(snapshot, results):
        if isinstance(result, (websockets.exceptions.ConnectionClosed, BrokenPipeError)):
            to_remove.add(client)
            log.warning("Dropping closed client %s", getattr(client, "remote_address", "?"))
        elif isinstance(result, Exception):
            log.error("Broadcast to %s failed: %r", getattr(client, "remote_address", "?"), result)
    clients.difference_update(to_remove)

async def broadcast_event(payload):
    """Broadcasts a (non-level) event and logs it."""
    log.info("=> %s%s", payload.get("type"), _detail(payload))
    await broadcast(json.dumps(payload))

async def broadcast_levels():
    """Periodically broadcasts audio levels."""
    while True:
        try:
            if clients:
                levels = audio_engine.get_levels()
                # For smooth UI, we send at ~20Hz (not logged: far too frequent)
                await broadcast(json.dumps({
                    "type": "audio_levels",
                    "rms_l": levels[0],
                    "rms_r": levels[1],
                    "peak_l": levels[2],
                    "peak_r": levels[3]
                }))
            await asyncio.sleep(0.05) # 20 FPS
        except Exception:
            log.exception("Level broadcast error")
            await asyncio.sleep(1)

async def loop_ticker():
    """Lets the monitor thread know the event loop is alive."""
    while True:
        sidecar_log.tick()
        await asyncio.sleep(1)

async def handle_websocket(websocket):
    """Handles incoming WebSocket connections and messages."""
    peer = getattr(websocket, "remote_address", "?")
    log.info("Client connected: %s (clients now %d)", peer, len(clients) + 1)
    clients.add(websocket)
    try:
        async for message in websocket:
            try:
                data = json.loads(message)
                command = data.get("command")
                level = log.debug if command in QUIET_COMMANDS else log.info
                level("<- %s %s", command, summarize({k: v for k, v in data.items() if k != "command"}))

                if command == "ping":
                    await send_json(websocket, {"type": "pong"})

                # --- MIDI Commands ---
                elif command == "list_devices":
                    devices = await asyncio.to_thread(midi_engine.list_devices)
                    await send_json(websocket, {
                        "type": "device_list",
                        "devices": devices
                    })

                elif command == "connect_device":
                    device_name = data.get("device_name")
                    try:
                        await asyncio.to_thread(midi_engine.connect, device_name)
                        await send_json(websocket, {
                            "type": "status",
                            "message": f"Connected to MIDI: {device_name}"
                        })
                    except Exception as e:
                        log.exception("MIDI connect failed for %s", device_name)
                        await send_json(websocket, {
                            "type": "error",
                            "message": str(e)
                        })

                # --- Audio Commands ---
                elif command == "list_audio_devices":
                    devices = await asyncio.to_thread(audio_engine.list_devices)
                    await send_json(websocket, {
                        "type": "audio_device_list",
                        "devices": devices
                    })

                elif command == "play_audio":
                    file_path = data.get("file_path")
                    device_id = data.get("device_id")
                    volume = data.get("volume", 1.0)
                    loop = data.get("loop", False)
                    output_channels = data.get("output_channels")
                    filter_type = data.get("filter_type", "none")
                    filter_freq = data.get("filter_frequency", 20000)

                    try:
                        loop_ref = asyncio.get_running_loop()

                        def on_finished(sid):
                            # Broadcast that audio finished naturally
                            asyncio.run_coroutine_threadsafe(
                                broadcast_event({
                                    "type": "audio_finished",
                                    "stream_id": sid
                                }),
                                loop_ref
                            )

                        stream_id, duration = await asyncio.to_thread(
                            audio_engine.play,
                            file_path, device_id, volume, loop,
                            on_finished=on_finished,
                            output_channels=output_channels,
                            filter_type=filter_type,
                            filter_freq=filter_freq
                        )
                        await send_json(websocket, {
                            "type": "audio_started",
                            "stream_id": stream_id,
                            "file_path": file_path,
                            "duration_seconds": duration,
                            "loop": loop,
                            "device_id": device_id
                        })
                    except Exception as e:
                        log.exception("Play failed for %s on device %s", file_path, device_id)
                        await send_json(websocket, {
                            "type": "error",
                            "message": f"Play Error: {str(e)}"
                        })

                elif command == "stop_audio":
                    stream_id = data.get("stream_id")
                    await asyncio.to_thread(audio_engine.stop, stream_id)
                    await send_json(websocket, {
                        "type": "audio_stopped",
                        "stream_id": stream_id
                    })

                elif command == "stop_all_audio":
                    await asyncio.to_thread(audio_engine.stop_all)
                    await send_json(websocket, {"type": "all_audio_stopped"})

                elif command == "set_master_volume":
                    vol = data.get("volume", 1.0)
                    audio_engine.set_master_volume(vol)

                elif command == "set_volume":
                    stream_id = data.get("stream_id")
                    vol = data.get("volume")
                    audio_engine.set_volume(stream_id, vol)

                elif command == "set_looping":
                    stream_id = data.get("stream_id")
                    loop = data.get("loop")
                    audio_engine.set_looping(stream_id, loop)
                    await broadcast_event({
                        "type": "audio_loop_updated",
                        "stream_id": stream_id,
                        "loop": loop
                    })

                elif command == "set_routing":
                    stream_id = data.get("stream_id")
                    channels = data.get("output_channels")
                    audio_engine.set_routing(stream_id, channels)

                elif command == "set_filter":
                    stream_id = data.get("stream_id")
                    filter_type = data.get("filter_type", "none")
                    freq = data.get("frequency", 20000)
                    audio_engine.set_filter(stream_id, filter_type, freq)

                elif command == "seek_audio":
                    stream_id = data.get("stream_id")
                    pos = data.get("position") # seconds
                    await asyncio.to_thread(audio_engine.seek, stream_id, pos)

                elif command == "unload_audio":
                    # A pad was cleared/replaced/deleted: stop its streams and free its decoded audio.
                    file_path = data.get("file_path")
                    await asyncio.to_thread(audio_engine.unload, file_path)
                    await send_json(websocket, {"type": "audio_unloaded", "file_path": file_path})

                elif command == "get_waveform":
                    file_path = data.get("file_path")
                    # Run in thread to avoid blocking loop
                    points = data.get("points", 100)
                    waveform, duration = await asyncio.to_thread(audio_engine.get_waveform, file_path, points)
                    await send_json(websocket, {
                        "type": "waveform_data",
                        "file_path": file_path,
                        "data": waveform,
                        "duration": duration
                    })

                elif command == "shutdown":
                    log.warning("Shutdown command received from %s", peer)
                    cleanup()
                    os._exit(0)

                else:
                    log.warning("Unknown command: %r", command)

            except json.JSONDecodeError:
                log.error("Invalid JSON from %s: %.200s", peer, message)
            except Exception as e:
                log.exception("Error processing command")
                await send_json(websocket, {"type": "error", "message": str(e)})

    except websockets.exceptions.ConnectionClosed as e:
        log.info("Client disconnected: %s code=%s reason=%r", peer, e.code, e.reason)
    except Exception:
        log.exception("WebSocket error for %s", peer)
    finally:
        if websocket in clients:
            clients.remove(websocket)
        log.info("Client removed: %s (clients now %d)", peer, len(clients))

def _loop_exception_handler(loop, context):
    log.error("Unhandled asyncio error: %s", context.get("message"), exc_info=context.get("exception"))

async def main():
    global midi_engine

    asyncio.get_running_loop().set_exception_handler(_loop_exception_handler)

    # Start watchdog
    threading.Thread(target=watchdog, name="watchdog", daemon=True).start()
    sidecar_log.install_signal_logging(cleanup)
    sidecar_log.start_monitor(
        lambda: f"clients={len(clients)} {audio_engine.stats()}"
    )

    midi_engine = MidiEngine(broadcast)
    await midi_engine.start_listener()
    loop = asyncio.get_running_loop()  # captured here: the callback runs on worker threads
    audio_engine.on_devices_changed = lambda: asyncio.run_coroutine_threadsafe(
        _announce_audio_devices(), loop
    )

    asyncio.create_task(loop_ticker())

    # Start Audio Level Broadcast Task
    asyncio.create_task(broadcast_levels())

    port = 8765
    max_port = 8775
    while port <= max_port:
        try:
            log.info("Starting WebSocket server on ws://127.0.0.1:%d", port)
            async with websockets.serve(
                handle_websocket,
                "127.0.0.1",
                port,
                ping_interval=None,
                ping_timeout=None
            ):
                log.info("WebSocket server listening on port %d", port)
                # The Flutter app waits for exactly this line (see sidecar_service.dart).
                print(f"PORT_BIND_SUCCESS:{port}", flush=True)
                await asyncio.Future()  # Run forever
        except OSError as e:
            if e.errno == errno_mod.EADDRINUSE:
                log.warning("Port %d in use, trying %d...", port, port + 1)
                port += 1
            else:
                log.exception("Socket error")
                raise e
        except Exception:
            log.exception("Unexpected error while serving")
            raise

    log.error("Could not find an available port for WebSocket server.")

async def _announce_audio_devices():
    """Tells the app the device list changed (e.g. after PortAudio re-init)."""
    devices = await asyncio.to_thread(audio_engine.list_devices)
    await broadcast_event({"type": "audio_device_list", "devices": devices})

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log.info("Stopping (KeyboardInterrupt)")
        cleanup()
    except BaseException:
        log.critical("Sidecar main exited with an exception", exc_info=True)
        raise
    log.info("Sidecar main finished")

import asyncio
import json
import websockets
import sys
import threading
import os
from audio_engine import AudioEngine
from midi_engine import MidiEngine

# Global Engines
audio_engine = AudioEngine()
midi_engine = None # Initialized in main

# Clients
clients = set()
verbose_command_logs = os.environ.get("PADVIBE_VERBOSE_COMMAND_LOGS", "0") == "1"

def cleanup():
    """Performs cleanup of engines before exiting."""
    print("Performing cleanup...")
    if midi_engine:
        midi_engine.stop()
    audio_engine.stop_all()

def watchdog():
    """Monitors the parent process and exits if it dies."""
    parent_pid = os.getppid()
    import time
    while True:
        try:
            # Check if parent process still exists
            os.kill(parent_pid, 0)
        except OSError:
            # Parent process died
            cleanup()
            os._exit(0)
        time.sleep(2)

async def broadcast(message):
    """Sends a message to all connected WebSocket clients."""
    if clients:
        # print(f"Broadcasting: {message[:100]}...") # Debug
        tasks = [client.send(message) for client in clients]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Cleanup closed clients based on results
        to_remove = set()
        for client, result in zip(clients, results):
            if isinstance(result, (websockets.exceptions.ConnectionClosed, BrokenPipeError)):
                to_remove.add(client)
        clients.difference_update(to_remove)

async def broadcast_levels():
    """Periodically broadcasts audio levels."""
    while True:
        try:
            if clients:
                levels = audio_engine.get_levels()
                # Only send if non-zero or occasionally to clear?
                # Optimization: Send only if changed significantly? 
                # For smooth UI, we send at ~30Hz
                await broadcast(json.dumps({
                    "type": "audio_levels",
                    "rms_l": levels[0],
                    "rms_r": levels[1],
                    "peak_l": levels[2],
                    "peak_r": levels[3]
                }))
            await asyncio.sleep(0.05) # 20 FPS
        except Exception as e:
            print(f"Level broadcast error: {e}")
            await asyncio.sleep(1)

async def handle_websocket(websocket):
    """Handles incoming WebSocket connections and messages."""
    print("Client connected", flush=True)
    clients.add(websocket)
    try:
        async for message in websocket:
            if verbose_command_logs:
                print(f"DEBUG RECEIVED COMMAND: {message[:200]}", flush=True)
            try:
                data = json.loads(message)
                command = data.get("command")

                # --- MIDI Commands ---
                if command == "list_devices":
                    devices = await asyncio.to_thread(midi_engine.list_devices)
                    await websocket.send(json.dumps({
                        "type": "device_list",
                        "devices": devices
                    }))

                elif command == "connect_device":
                    device_name = data.get("device_name")
                    try:
                        await asyncio.to_thread(midi_engine.connect, device_name)
                        await websocket.send(json.dumps({
                            "type": "status", 
                            "message": f"Connected to MIDI: {device_name}"
                        }))
                    except Exception as e:
                        await websocket.send(json.dumps({
                            "type": "error", 
                            "message": str(e)
                        }))

                # --- Audio Commands ---
                elif command == "list_audio_devices":
                    devices = await asyncio.to_thread(audio_engine.list_devices)
                    await websocket.send(json.dumps({
                        "type": "audio_device_list",
                        "devices": devices
                    }))

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
                                broadcast(json.dumps({
                                    "type": "audio_finished",
                                    "stream_id": sid
                                })), 
                                loop_ref
                            )

                        stream_id, duration = await asyncio.to_thread(
                            audio_engine.play,
                            file_path, device_id, volume, loop,
                            on_finished=lambda: on_finished(stream_id),
                            output_channels=output_channels,
                            filter_type=filter_type,
                            filter_freq=filter_freq
                        )
                        await websocket.send(json.dumps({
                            "type": "audio_started",
                            "stream_id": stream_id,
                            "file_path": file_path,
                            "duration_seconds": duration,
                            "loop": loop,
                            "device_id": device_id
                        }))
                    except Exception as e:
                        await websocket.send(json.dumps({
                            "type": "error", 
                            "message": f"Play Error: {str(e)}"
                        }))

                elif command == "stop_audio":
                    stream_id = data.get("stream_id")
                    await asyncio.to_thread(audio_engine.stop, stream_id)
                    await websocket.send(json.dumps({
                        "type": "audio_stopped", 
                        "stream_id": stream_id
                    }))

                elif command == "stop_all_audio":
                    await asyncio.to_thread(audio_engine.stop_all)
                    await websocket.send(json.dumps({
                        "type": "all_audio_stopped"
                    }))

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
                    await broadcast(json.dumps({
                        "type": "audio_loop_updated",
                        "stream_id": stream_id,
                        "loop": loop
                    }))

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

                elif command == "get_waveform":
                    file_path = data.get("file_path")
                    # Run in thread to avoid blocking loop
                    points = data.get("points", 100)
                    waveform, duration = await asyncio.to_thread(audio_engine.get_waveform, file_path, points)
                    await websocket.send(json.dumps({
                        "type": "waveform_data",
                        "file_path": file_path,
                        "data": waveform,
                        "duration": duration
                    }))

                elif command == "shutdown":
                    print("Shutdown command received")
                    cleanup()
                    os._exit(0)

            except json.JSONDecodeError:
                print(f"Invalid JSON: {message}")
            except Exception as e:
                print(f"Error processing command: {e}")
                await websocket.send(json.dumps({"type": "error", "message": str(e)}))

    except websockets.exceptions.ConnectionClosed as e:
        print(f"Client disconnected: {e.code} ({e.reason})", flush=True)
    except Exception as e:
        print(f"WebSocket error: {e}", flush=True)
    finally:
        if websocket in clients:
            clients.remove(websocket)

async def main():
    global midi_engine
    
    # Start watchdog
    threading.Thread(target=watchdog, daemon=True).start()
    
    midi_engine = MidiEngine(broadcast)
    
    # Start MIDI Listener Task
    asyncio.create_task(midi_engine.start_listener())
    
    # Start Audio Level Broadcast Task
    asyncio.create_task(broadcast_levels())

    port = 8765
    max_port = 8775
    while port <= max_port:
        try:
            print(f"Starting WebSocket server on ws://127.0.0.1:{port}", flush=True)
            async with websockets.serve(
                handle_websocket, 
                "127.0.0.1", 
                port,
                ping_interval=None,
                ping_timeout=None
            ):
                print(f"PORT_BIND_SUCCESS:{port}", flush=True)
                await asyncio.Future()  # Run forever
        except OSError as e:
            if e.errno == 48: # Address already in use
                print(f"Port {port} in use, trying {port + 1}...")
                port += 1
            else:
                print(f"Socket error: {e}")
                raise e
        except Exception as e:
            print(f"Unexpected error: {e}")
            raise e
    
    print("Could not find an available port for WebSocket server.")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("Stopping...")
        cleanup()

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
        if os.getppid() != parent_pid:
            # Parent changed or died
            cleanup()
            os._exit(0)
        time.sleep(1)

async def broadcast(message):
    """Sends a message to all connected WebSocket clients."""
    if clients:
        # Filter out closed clients
        to_remove = set()
        for client in clients:
            try:
                await client.send(message)
            except websockets.exceptions.ConnectionClosed:
                to_remove.add(client)
        clients.difference_update(to_remove)

async def handle_websocket(websocket):
    """Handles incoming WebSocket connections and messages."""
    print("Client connected")
    clients.add(websocket)
    try:
        async for message in websocket:
            try:
                data = json.loads(message)
                command = data.get("command")

                # --- MIDI Commands ---
                if command == "list_devices":
                    devices = midi_engine.list_devices()
                    await websocket.send(json.dumps({
                        "type": "device_list",
                        "devices": devices
                    }))

                elif command == "connect_device":
                    device_name = data.get("device_name")
                    try:
                        midi_engine.connect(device_name)
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
                    devices = audio_engine.list_devices()
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

                        stream_id, duration = audio_engine.play(
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
                    audio_engine.stop(stream_id)
                    await websocket.send(json.dumps({
                        "type": "audio_stopped", 
                        "stream_id": stream_id
                    }))

                elif command == "stop_all_audio":
                    audio_engine.stop_all()
                    await websocket.send(json.dumps({
                        "type": "all_audio_stopped"
                    }))

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
                    audio_engine.seek(stream_id, pos)

                elif command == "get_waveform":
                    file_path = data.get("file_path")
                    # Run in thread to avoid blocking loop
                    points = data.get("points", 100)
                    waveform = await asyncio.to_thread(audio_engine.get_waveform, file_path, points)
                    await websocket.send(json.dumps({
                        "type": "waveform_data",
                        "file_path": file_path,
                        "data": waveform
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

    except websockets.exceptions.ConnectionClosed:
        print("Client disconnected")
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

    print("Starting WebSocket server on ws://127.0.0.1:8765", flush=True)
    async with websockets.serve(handle_websocket, "127.0.0.1", 8765):
        await asyncio.Future()  # Run forever

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("Stopping...")
        cleanup()
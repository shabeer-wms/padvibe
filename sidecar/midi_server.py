import asyncio
import json
import mido
import websockets
import sys

# Store connected WebSocket clients
clients = set()

# Store the currently connected MIDI input port
current_input_port = None

async def handle_midi_input():
    """Reads MIDI messages from the current input port and broadcasts them."""
    global current_input_port
    print("MIDI Input Handler Started")
    while True:
        if current_input_port:
            for msg in current_input_port.iter_pending():
                # print(f"MIDI Message: {msg}")
                if msg.type in ['note_on', 'note_off']:
                    data = {
                        "type": "midi_message",
                        "message": {
                            "type": msg.type,
                            "note": msg.note,
                            "velocity": msg.velocity,
                            "channel": msg.channel
                        }
                    }
                    await broadcast(json.dumps(data))
        await asyncio.sleep(0.001) # Small sleep to prevent high CPU usage

async def broadcast(message):
    """Sends a message to all connected WebSocket clients."""
    if clients:
        await asyncio.gather(*[client.send(message) for client in clients])

async def handle_websocket(websocket):
    """Handles incoming WebSocket connections and messages."""
    print("Client connected")
    clients.add(websocket)
    try:
        async for message in websocket:
            try:
                data = json.loads(message)
                command = data.get("command")

                if command == "list_devices":
                    devices = mido.get_input_names()
                    response = {
                        "type": "device_list",
                        "devices": devices
                    }
                    await websocket.send(json.dumps(response))

                elif command == "connect_device":
                    device_name = data.get("device_name")
                    connect_midi_device(device_name)
                    await websocket.send(json.dumps({"type": "status", "message": f"Connected to {device_name}"}))

            except json.JSONDecodeError:
                print(f"Invalid JSON received: {message}")
            except Exception as e:
                print(f"Error processing message: {e}")
                await websocket.send(json.dumps({"type": "error", "message": str(e)}))

    except websockets.exceptions.ConnectionClosed:
        print("Client disconnected")
    finally:
        clients.remove(websocket)

def connect_midi_device(device_name):
    """Connects to a specific MIDI input device."""
    global current_input_port
    
    if current_input_port:
        print(f"Closing current port: {current_input_port.name}")
        current_input_port.close()
        current_input_port = None

    try:
        current_input_port = mido.open_input(device_name)
        print(f"Connected to MIDI device: {device_name}")
    except Exception as e:
        print(f"Failed to connect to {device_name}: {e}")
        raise e

async def main():
    # Start the WebSocket server
    print("Starting WebSocket server...", flush=True)
    server = await websockets.serve(handle_websocket, "127.0.0.1", 8765)
    print("WebSocket server started on ws://127.0.0.1:8765", flush=True)

    # Run the MIDI input handler concurrently
    asyncio.create_task(handle_midi_input())

    # Keep the server running
    await asyncio.Future()  # Run forever

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("Server stopping...")
        if current_input_port:
            current_input_port.close()

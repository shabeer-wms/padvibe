import mido
import asyncio
import json

class MidiEngine:
    def __init__(self, broadcast_callback):
        self.broadcast = broadcast_callback
        self.current_input_port = None
        self.running = False

    def list_devices(self):
        try:
            return mido.get_input_names()
        except Exception as e:
            print(f"Error listing MIDI devices: {e}")
            return []

    def connect(self, device_name):
        if self.current_input_port:
            self.current_input_port.close()
            self.current_input_port = None
        
        try:
            self.current_input_port = mido.open_input(device_name)
            print(f"Connected to MIDI: {device_name}")
        except Exception as e:
            print(f"Failed to connect MIDI: {e}")
            raise e

    async def start_listener(self):
        print("MIDI Listener Started")
        self.running = True
        while self.running:
            if self.current_input_port:
                for msg in self.current_input_port.iter_pending():
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
                        await self.broadcast(json.dumps(data))
            await asyncio.sleep(0.001)

    def stop(self):
        self.running = False
        if self.current_input_port:
            self.current_input_port.close()

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
                    if msg.type in ['note_on', 'note_off', 'control_change', 'program_change', 'polytouch', 'aftertouch', 'pitchwheel']:
                        data = {
                            "type": "midi_message",
                            "message": {
                                "type": msg.type,
                                "channel": msg.channel,
                            }
                        }

                        if msg.type in ['note_on', 'note_off']:
                            data["message"]["note"] = msg.note
                            data["message"]["velocity"] = msg.velocity
                        elif msg.type == 'control_change':
                            data["message"]["control"] = msg.control
                            data["message"]["value"] = msg.value
                        elif msg.type == 'program_change':
                            data["message"]["program"] = msg.program
                        elif msg.type == 'polytouch':
                            data["message"]["note"] = msg.note
                            data["message"]["value"] = msg.value
                        elif msg.type == 'aftertouch':
                            data["message"]["value"] = msg.value
                        elif msg.type == 'pitchwheel':
                            data["message"]["pitch"] = msg.pitch
                        
                        await self.broadcast(json.dumps(data))
            await asyncio.sleep(0.001)

    def stop(self):
        self.running = False
        if self.current_input_port:
            self.current_input_port.close()

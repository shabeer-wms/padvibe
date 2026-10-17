import mido
import asyncio
import json
import logging

log = logging.getLogger("sidecar.midi")


def _message_to_dict(msg):
    """Converts a mido message to the JSON shape the Flutter UI expects.

    Returns None for message types the UI does not handle.
    """
    if msg.type not in ('note_on', 'note_off', 'control_change', 'program_change',
                        'polytouch', 'aftertouch', 'pitchwheel'):
        return None

    message = {"type": msg.type, "channel": msg.channel}
    if msg.type in ('note_on', 'note_off'):
        message["note"] = msg.note
        message["velocity"] = msg.velocity
    elif msg.type == 'control_change':
        message["control"] = msg.control
        message["value"] = msg.value
    elif msg.type == 'program_change':
        message["program"] = msg.program
    elif msg.type == 'polytouch':
        message["note"] = msg.note
        message["value"] = msg.value
    elif msg.type == 'aftertouch':
        message["value"] = msg.value
    elif msg.type == 'pitchwheel':
        message["pitch"] = msg.pitch
    return {"type": "midi_message", "message": message}


class MidiEngine:
    def __init__(self, broadcast_callback):
        self.broadcast = broadcast_callback
        self.current_input_port = None
        self.running = False
        self._loop = None

    def list_devices(self):
        try:
            names = mido.get_input_names()
            log.info("MIDI input devices: %s", names)
            return names
        except Exception as e:
            log.exception("Error listing MIDI devices")
            return []

    def _on_message(self, msg):
        """Runs on the rtmidi thread; hands the message to the asyncio loop."""
        log.debug("MIDI in: %s", msg)
        data = _message_to_dict(msg)
        if data is None or self._loop is None or self._loop.is_closed():
            return
        asyncio.run_coroutine_threadsafe(self.broadcast(json.dumps(data)), self._loop)

    def connect(self, device_name):
        if self.current_input_port:
            self.current_input_port.close()
            self.current_input_port = None

        try:
            # Event-driven: rtmidi invokes the callback, no polling loop needed.
            self.current_input_port = mido.open_input(device_name, callback=self._on_message)
            log.info("Connected to MIDI input: %s", device_name)
        except Exception:
            log.exception("Failed to connect MIDI input %s", device_name)
            raise

    async def start_listener(self):
        self._loop = asyncio.get_running_loop()
        self.running = True
        log.info("MIDI listener started")

    def stop(self):
        log.info("MIDI engine stopping")
        self.running = False
        if self.current_input_port:
            self.current_input_port.close()
            self.current_input_port = None

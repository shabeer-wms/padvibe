"""Checks the audio engine's decode cache and playback callback without a sound card.
Run: python sidecar/test_audio_engine.py"""
import math
import os
import struct
import sys
import tempfile
import threading
import time
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from audio_engine import AudioCache, AudioEngine, _Stream  # noqa: E402


def make_wav(path, seconds, amplitude=0.5, rate=8000):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", int(32767 * amplitude)) for _ in range(int(seconds * rate))))


def run_stream(engine, audio, loop, blocks, volume=1.0):
    finished = []
    s = _Stream("x.wav", audio, None, volume, loop, lambda sid: finished.append(sid), None, "none", 20000)
    s.fade_remaining = 0
    out_blocks = []
    for _ in range(blocks):
        out = np.zeros((1024, 2), dtype="float32")
        try:
            engine._fill(s, 0, out, 1024, None)
        except Exception as e:  # sd.CallbackStop ends the stream
            if type(e).__name__ != "CallbackStop":
                raise
            out_blocks.append(out)
            break
        out_blocks.append(out)
    return s, out_blocks, finished


def main():
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "a.wav")
        make_wav(wav, 0.5)  # 4000 frames

        # 1. The cache decodes once and then hits.
        cache = AudioCache()
        first = cache.load(wav)
        assert cache.load(wav) is first, "second load should be a cache hit"
        assert first.frames == 4000 and first.channels == 1

        # 2. Playing and looping never modifies the shared decoded data.
        engine = AudioEngine()
        before = first.data.copy()
        s, blocks, _ = run_stream(engine, first, loop=True, blocks=20, volume=0.5)
        assert np.array_equal(first.data, before), "decoded audio was modified by playback"
        peaks = [float(np.abs(b).max()) for b in blocks]
        assert max(peaks) - min(peaks) < 1e-6, f"loop volume drifted: {peaks[:3]}...{peaks[-3:]}"

        # 3. A non-looping stream ends and reports it.
        s, blocks, finished = run_stream(engine, first, loop=False, blocks=20)
        assert s.finished and finished == [0], "non-looping stream should finish once"
        assert len(blocks) == 4, f"4000 frames = 4 blocks of 1024, got {len(blocks)}"

        # 4. Editing the file invalidates the cache entry.
        time.sleep(0.01)
        make_wav(wav, 1.0)
        assert cache.load(wav).frames == 8000, "changed file should be decoded again"

        # 5. Evicting frees the memory; an empty file cannot hang a looping stream.
        assert cache.evict(wav) and cache.total_bytes == 0
        empty = os.path.join(tmp, "empty.wav")
        make_wav(empty, 0)
        e = cache.load(empty)
        s, _, finished = run_stream(engine, e, loop=True, blocks=3)
        assert s.finished, "looping an empty file must end"

        # 6. Waveform comes from the same decoded data.
        peaks, duration = engine.get_waveform(wav, 10)
        assert len(peaks) == 10 and abs(duration - 1.0) < 1e-6 and max(peaks) == 1.0

        # 6b. A stream being torn down goes silent but never ends itself (that
        #     races with the abort() from the engine thread).
        s_closed = _Stream("x.wav", first, None, 1.0, True, lambda sid: None, None, "none", 20000)
        s_closed.closed = True
        out = np.ones((1024, 2), dtype="float32")
        engine._fill(s_closed, 0, out, 1024, None)  # must not raise CallbackStop
        assert not out.any(), "a closed stream must output silence"

        # 7. A slow native stop (CoreAudio waiting on a device) must never freeze
        #    the event loop: get_levels() runs there 20x/second and used to wait
        #    for the lock that stop() held during the native call.
        class SlowStream:
            active = True
            def abort(self): time.sleep(1.5)
            def close(self): pass

        slow = _Stream("slow.wav", first, None, 1.0, True, lambda sid: None, None, "none", 20000)
        slow.stream = SlowStream()
        engine.streams[99] = slow
        stopper = threading.Thread(target=engine.stop, args=(99,))
        stopper.start()
        time.sleep(0.2)  # stop() is now inside the slow native call
        t0 = time.perf_counter()
        engine.get_levels()
        engine.set_volume(5, 0.5)
        lag = time.perf_counter() - t0
        stopper.join()
        assert lag < 0.2, f"event-loop calls blocked for {lag:.2f}s behind a slow stop"
        assert 99 not in engine.streams
    print("PASS")


if __name__ == "__main__":
    main()

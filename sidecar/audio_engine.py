import concurrent.futures
import logging
import os
import threading
import time
from collections import OrderedDict, namedtuple

import numpy as np
import sounddevice as sd
import soundfile as sf

log = logging.getLogger("sidecar.audio")

DecodedAudio = namedtuple("DecodedAudio", "data samplerate channels frames nbytes mtime size")


class AudioCache:
    """Decoded audio kept in memory.

    A file is decoded once, then every play and its waveform reuse that array,
    so a pad starts instantly instead of re-decoding (mp3 decoding is the slow
    part). Entries are dropped least-recently-used once the budget is exceeded,
    when the file changes on disk, or explicitly via evict(). Files too large
    to hold in memory are not cached; playback streams them from disk.
    """

    def __init__(self, budget_bytes=600 * 1024 * 1024, max_file_bytes=100 * 1024 * 1024):
        self.budget_bytes = budget_bytes
        self.max_file_bytes = max_file_bytes
        self._entries = OrderedDict()  # path -> DecodedAudio, least recently used first
        self._total = 0
        self._lock = threading.Lock()
        self._path_locks = {}  # one decode per file at a time; different files decode in parallel

    @property
    def total_bytes(self):
        return self._total

    def __len__(self):
        return len(self._entries)

    def load(self, path):
        """Returns the DecodedAudio for path, decoding it if needed, or None if
        the file is too large to cache. Raises if the file cannot be read."""
        st = os.stat(path)
        with self._lock:
            path_lock = self._path_locks.setdefault(path, threading.Lock())
        with path_lock:
            with self._lock:
                entry = self._entries.get(path)
                if entry and entry.mtime == st.st_mtime_ns and entry.size == st.st_size:
                    self._entries.move_to_end(path)
                    log.debug("Cache hit: %s", os.path.basename(path))
                    return entry

            info = sf.info(path)
            if info.frames * info.channels * 4 > self.max_file_bytes:
                log.info("Not caching %s: %.0fMB decoded exceeds the %.0fMB per-file limit",
                         os.path.basename(path), info.frames * info.channels * 4 / 1e6, self.max_file_bytes / 1e6)
                return None

            t0 = time.monotonic()
            data, samplerate = sf.read(path, dtype="float32", always_2d=True)
            entry = DecodedAudio(data, samplerate, data.shape[1], len(data), data.nbytes, st.st_mtime_ns, st.st_size)
            log.info("Decoded %s: %d frames, %d ch, %d Hz, %.1fMB in %.0fms",
                     os.path.basename(path), entry.frames, entry.channels, samplerate,
                     entry.nbytes / 1e6, (time.monotonic() - t0) * 1000)

            with self._lock:
                old = self._entries.pop(path, None)
                if old:
                    self._total -= old.nbytes
                self._entries[path] = entry
                self._total += entry.nbytes
                while self._total > self.budget_bytes and len(self._entries) > 1:
                    victim, dropped = self._entries.popitem(last=False)
                    self._total -= dropped.nbytes
                    log.info("Cache full: evicted %s (%.1fMB)", os.path.basename(victim), dropped.nbytes / 1e6)
            return entry

    def evict(self, path):
        with self._lock:
            entry = self._entries.pop(path, None)
            self._path_locks.pop(path, None)
            if entry:
                self._total -= entry.nbytes
        if entry:
            log.info("Evicted %s from cache (%.1fMB freed)", os.path.basename(path), entry.nbytes / 1e6)
        return entry is not None


class _Stream:
    """State of one playing sound, shared between the audio callback and commands."""

    def __init__(self, path, audio, file, volume, loop, on_finished, output_channels, filter_type, filter_freq):
        self.path = path
        self.data = audio.data if audio else None  # decoded samples (shared, never modified)
        self.file = file                           # SoundFile when streaming from disk
        self.samplerate = audio.samplerate if audio else file.samplerate
        self.channels = audio.channels if audio else file.channels
        self.frames = audio.frames if audio else file.frames
        self.cursor = 0
        self.volume = volume
        self.loop = loop
        self.finished = False
        self.closed = False
        self.on_finished = on_finished
        self.on_finished_called = False
        self.output_channels = output_channels
        self.filter_type = filter_type
        self.filter_freq = filter_freq
        self.fade_total = int(0.01 * self.samplerate)  # 10ms fade-in avoids a click
        self.fade_remaining = self.fade_total
        self.underflows = 0
        self.last_status_log = 0.0
        self.stream = None

    def notify_finished(self, stream_id):
        if not self.on_finished_called and self.on_finished:
            self.on_finished_called = True
            self.on_finished(stream_id)


class AudioEngine:
    def __init__(self):
        self.streams = {}  # stream_id -> _Stream
        self.next_stream_id = 0
        self.lock = threading.RLock()
        self.master_volume = 1.0
        # Current RMS/Peak per stream: { stream_id: (rms_l, rms_r, peak_l, peak_r) }
        self.stream_levels = {}
        self._initialized = False
        self.device_cache = {}
        self.cache = AudioCache()
        # PortAudio must not be re-initialised while another thread opens a stream
        # or queries devices (that can crash natively), so those are serialised.
        # Only worker threads take this lock, never the asyncio event loop: the
        # native calls it guards (open, abort, close) can block for a long time.
        self._pa_lock = threading.RLock()
        # Streams that finished on their own are torn down here, off the event loop.
        self._closer = concurrent.futures.ThreadPoolExecutor(max_workers=1, thread_name_prefix="audio-closer")
        # Set by the server; called (from any thread) when device indices changed.
        self.on_devices_changed = None

    # ── Devices ────────────────────────────────────────────────────────────

    def _ensure_initialized(self):
        with self._pa_lock:
            self._ensure_initialized_locked()

    def _ensure_initialized_locked(self):
        if not self._initialized:
            try:
                sd._terminate()
                sd._initialize()
                self._initialized = True
                log.info("PortAudio initialized: %s", sd.get_portaudio_version()[1])
            except Exception:
                log.exception("PortAudio initialization failed")

    def list_devices(self):
        """Returns a list of available output devices."""
        self._ensure_initialized()
        try:
            with self._pa_lock:
                devices = sd.query_devices()
                hostapis = sd.query_hostapis()
            output_devices = []
            new_cache = {}
            for i, dev in enumerate(devices):
                if dev['max_output_channels'] > 0:
                    api_index = dev['hostapi']
                    api_name = hostapis[api_index]['name'] if api_index < len(hostapis) else str(api_index)
                    dev_info = {
                        "id": i,
                        "name": dev['name'],
                        "hostapi": api_name,
                        "channels": dev['max_output_channels']
                    }
                    output_devices.append(dev_info)
                    new_cache[i] = dev_info

            with self.lock:
                self.device_cache = new_cache

            log.info(
                "Audio output devices: %s | default output=%s",
                [f"{d['id']}:{d['name']}" for d in output_devices],
                sd.default.device[1],
            )
            return output_devices
        except Exception:
            log.exception("Listing audio devices failed")
            return []

    def _output_channels_for(self, device_id):
        """Returns (device_id, channel count) for a device, resolving the default."""
        with self.lock:
            known = self.device_cache.get(device_id)
        if known is not None:
            return device_id, known['channels']
        try:  # a native call: never made while holding self.lock
            target = device_id if device_id is not None else sd.default.device[1]
            with self.lock:
                known = self.device_cache.get(target)
            if known is not None:
                return target, known['channels']
            channels = sd.query_devices(target, 'output')['max_output_channels']
            with self.lock:
                self.device_cache[target] = {"channels": channels}
            return target, channels
        except Exception:
            return device_id, 2

    # ── Playback ───────────────────────────────────────────────────────────

    def play(self, file_path, device_id=None, volume=1.0, loop=False, on_finished=None, output_channels=None, filter_type='none', filter_freq=20000):
        """Plays an audio file on a specific device."""
        self._ensure_initialized()
        device_id, max_ch = self._output_channels_for(device_id)

        log.info(
            "Play request: file=%s device=%s volume=%s loop=%s channels=%s filter=%s",
            file_path, device_id, volume, loop, output_channels, filter_type,
        )
        try:
            if not os.path.exists(file_path):
                log.error("File does not exist: %s", file_path)
                raise FileNotFoundError(f"File not found: {file_path}")

            audio = self.cache.load(file_path)  # instant when already decoded
            file = None
            if audio is None:  # too large to hold in memory: stream from disk
                file = sf.SoundFile(file_path)
                log.info("Streaming %s from disk: %d Hz, %d ch, %d frames",
                         os.path.basename(file_path), file.samplerate, file.channels, file.frames)

            s = _Stream(file_path, audio, file, volume, loop, on_finished, output_channels, filter_type, filter_freq)
            with self.lock:
                stream_id = self.next_stream_id
                self.next_stream_id += 1

            with self._pa_lock:
                s.stream = self._start_stream(device_id, s.samplerate, max_ch, self._make_callback(s, stream_id))
            with self.lock:
                self.streams[stream_id] = s

            duration = s.frames / s.samplerate
            log.info("Stream %s started: %s (%.2fs) on device %s", stream_id, os.path.basename(file_path), duration, device_id)
            return stream_id, duration

        except Exception:
            log.exception("Error starting playback of %s", file_path)
            raise

    def _make_callback(self, s, stream_id):
        def callback(outdata, frames, time_info, status):
            try:
                self._fill(s, stream_id, outdata, frames, status)
            except sd.CallbackStop:
                raise
            except Exception as e:
                # A decode/seek error mid-stream (e.g. a corrupt file) must end
                # this stream cleanly instead of aborting PortAudio's thread.
                log.error("Callback error on stream %s, stopping it: %r", stream_id, e, exc_info=True)
                outdata.fill(0)
                s.finished = True
                s.notify_finished(stream_id)
                raise sd.CallbackStop
        return callback

    def _next_block(self, s, frames):
        """Up to `frames` samples shaped (n, channels), looping if asked. Fewer
        than requested means the end was reached (and s.finished is set)."""
        parts, got, empty_rewinds = [], 0, 0
        while got < frames:
            want = frames - got
            if s.data is not None:
                chunk = s.data[s.cursor:s.cursor + want]
                s.cursor += len(chunk)
            else:
                chunk = s.file.read(want, dtype='float32', always_2d=True)
            if len(chunk):
                parts.append(chunk)
                got += len(chunk)
                empty_rewinds = 0
            if got < frames:  # reached the end
                if s.loop and empty_rewinds < 2:  # rewinding an empty file would spin forever
                    if s.data is not None:
                        s.cursor = 0
                    else:
                        s.file.seek(0)
                    empty_rewinds += 1
                else:
                    s.finished = True
                    break
        if not parts:
            return np.zeros((0, s.channels), dtype='float32')
        return parts[0] if len(parts) == 1 else np.concatenate(parts)

    def _fill(self, s, stream_id, outdata, frames, status):
        if status:
            # PortAudio reports underflow/overflow here; rate-limit the log.
            s.underflows += 1
            now = time.monotonic()
            if now - s.last_status_log > 5:
                s.last_status_log = now
                log.warning("Stream %s audio status: %s (occurrences so far: %d)", stream_id, status, s.underflows)

        outdata.fill(0)
        if s.closed:
            # The engine is tearing this stream down (abort() from another thread).
            # Stay quiet and do NOT stop it from here: PortAudio can deadlock when the
            # callback ends a stream at the same moment another thread stops it.
            return
        if s.finished:
            s.notify_finished(stream_id)
            raise sd.CallbackStop

        block = self._next_block(s, frames)
        n = len(block)
        if n:
            # A new array: the decoded data is shared and must never be modified.
            block = block * (s.volume * self.master_volume)
            if s.fade_remaining > 0:
                fade = min(n, s.fade_remaining)
                done = s.fade_total - s.fade_remaining
                ramp = np.linspace(done / s.fade_total, (done + fade) / s.fade_total, fade, dtype='float32')
                block[:fade] *= ramp[:, None]
                s.fade_remaining -= fade

            self._route(block, outdata, s.output_channels)

            # Soft-knee limiter: squashes peaks near 1.0 instead of clipping.
            np.tanh(outdata[:n], out=outdata[:n])

            # Meter what is actually heard on hardware channels 0 and 1.
            heard = outdata[:n]
            peaks = np.max(np.abs(heard), axis=0)
            rms = np.sqrt(np.mean(heard ** 2, axis=0))
            self.stream_levels[stream_id] = (
                float(rms[0]), float(rms[1]) if len(rms) > 1 else 0.0,
                float(peaks[0]), float(peaks[1]) if len(peaks) > 1 else 0.0,
            )
        else:
            self.stream_levels[stream_id] = (0.0, 0.0, 0.0, 0.0)

        if s.finished:
            s.notify_finished(stream_id)
            raise sd.CallbackStop

    @staticmethod
    def _route(block, outdata, targets):
        """Copies block (n, channels) into outdata, honouring per-pad routing."""
        n, ch_in = block.shape
        out_ch = outdata.shape[1]
        if targets is None:
            if ch_in == 1 and out_ch >= 2:
                outdata[:n, 0] = block[:, 0]
                outdata[:n, 1] = block[:, 0]
            elif ch_in == out_ch:
                outdata[:n] = block
            else:
                m = min(ch_in, out_ch)
                outdata[:n, :m] = block[:, :m]
        else:
            for i, target in enumerate(targets):
                if 0 <= target < out_ch:
                    outdata[:n, target] = block[:, i % ch_in]

    def _start_stream(self, device_id, samplerate, channels, callback):
        """Opens and starts an output stream, recovering from device errors
        (e.g. PaMacCore -9986 "Unspecified Audio Hardware Error").

        PortAudio numbers devices once, when it initialises. If a device is
        plugged, unplugged or reconfigured afterwards (a display going to sleep,
        a USB/Bluetooth interface, a sample-rate change by another app) those
        numbers go stale and opening the old index fails. Recovery: remember the
        device's name, re-initialise PortAudio (only possible when nothing else
        is playing, as it closes every stream), look the name up again, and
        retry; otherwise fall back to the system default."""
        def open_(dev, ch):
            log.info("Opening output stream: device=%s samplerate=%s channels=%s", dev, samplerate, ch)
            stream = sd.OutputStream(
                device=dev,
                samplerate=samplerate,
                channels=ch,
                callback=callback,
                latency='low',
                blocksize=1024,
            )
            stream.start()
            log.info("Output stream started: device=%s latency=%.1fms", dev, stream.latency * 1000)
            return stream

        with self.lock:
            wanted_name = self.device_cache.get(device_id, {}).get("name") if device_id is not None else None

        try:
            return open_(device_id, channels)
        except Exception as e:
            log.error("Failed to start stream on device %s (%s): %s", device_id, wanted_name, e)
            self._log_device_snapshot("at failure")

        with self.lock:
            idle = not self.streams
        if idle:
            try:
                sd._terminate()
                sd._initialize()
                with self.lock:
                    self.device_cache = {}
                log.warning("PortAudio re-initialised after stream failure")
                self._log_device_snapshot("after re-init")
                new_id = self._find_device_by_name(wanted_name) if wanted_name else device_id
                if self.on_devices_changed:
                    try:
                        self.on_devices_changed()
                    except Exception:
                        log.exception("on_devices_changed callback failed")
                if new_id is not None:
                    if new_id != device_id:
                        log.warning("Device %r moved from index %s to %s", wanted_name, device_id, new_id)
                    return open_(new_id, channels)
                log.warning("Device %r is no longer present", wanted_name)
            except Exception:
                log.exception("Recovery after re-init failed for device %s", device_id)
        else:
            log.warning("Cannot re-initialise PortAudio while other streams are playing")

        log.warning("Falling back to default output device")
        return open_(None, 2)

    def _find_device_by_name(self, name):
        for i, dev in enumerate(sd.query_devices()):
            if dev['max_output_channels'] > 0 and dev['name'] == name:
                return i
        return None

    def _log_device_snapshot(self, when):
        try:
            names = [f"{i}:{d['name']}(out={d['max_output_channels']})" for i, d in enumerate(sd.query_devices())]
            log.info("Devices %s: %s | default=%s", when, names, sd.default.device)
        except Exception:
            log.exception("Could not snapshot devices %s", when)

    # ── Control ────────────────────────────────────────────────────────────

    def stop(self, stream_id):
        with self.lock:
            s = self.streams.get(stream_id)
            if s is not None:
                self._detach_locked(stream_id, s)
        if s is None:
            log.debug("Stop requested for unknown stream %s", stream_id)
            return
        log.info("Stopping stream %s", stream_id)
        self._teardown(stream_id, s)

    def stop_all(self):
        with self.lock:
            detached = [(sid, self._detach_locked(sid, s)) for sid, s in list(self.streams.items())]
        log.info("Stopping all streams: %s", [sid for sid, _ in detached])
        for sid, s in detached:
            self._teardown(sid, s)

    def unload(self, file_path):
        """Forgets a file (its pad was cleared or removed): stops anything still
        playing it and frees its decoded audio."""
        with self.lock:
            detached = [
                (sid, self._detach_locked(sid, s))
                for sid, s in list(self.streams.items()) if s.path == file_path
            ]
        for sid, s in detached:
            log.info("Stopping stream %s: its file was unloaded", sid)
            self._teardown(sid, s)
        freed = self.cache.evict(file_path)
        log.info("Unloaded %s (was cached: %s; cache now %d files, %.1fMB)",
                 os.path.basename(file_path), freed, len(self.cache), self.cache.total_bytes / 1e6)

    def set_master_volume(self, volume):
        with self.lock:
            self.master_volume = max(0.0, min(1.0, volume))

    def set_volume(self, stream_id, volume):
        if volume is None:
            return
        with self.lock:
            if stream_id in self.streams:
                self.streams[stream_id].volume = volume

    def set_looping(self, stream_id, loop):
        with self.lock:
            if stream_id in self.streams:
                self.streams[stream_id].loop = loop

    def set_routing(self, stream_id, output_channels):
        with self.lock:
            if stream_id in self.streams:
                self.streams[stream_id].output_channels = output_channels

    def set_filter(self, stream_id, filter_type, freq):
        """Updates filter parameters for a stream."""
        with self.lock:
            if stream_id in self.streams:
                s = self.streams[stream_id]
                s.filter_type = filter_type
                s.filter_freq = freq

    def seek(self, stream_id, position_seconds):
        """Seeks to a specific position in seconds."""
        with self.lock:
            s = self.streams.get(stream_id)
            if s is None:
                return
            if s.closed:
                log.warning("Seek on stream %s ignored: already closed", stream_id)
                return
            target = max(0, min(int(position_seconds * s.samplerate), s.frames))
            log.info("Seek stream %s to %.2fs", stream_id, position_seconds)
            if s.data is not None:
                s.cursor = target
            else:
                s.file.seek(target)
            s.finished = False

    def get_levels(self):
        """Returns aggregated master levels (rms_l, rms_r, peak_l, peak_r, spectrum).

        Runs on the asyncio event loop 20 times a second, so it must never wait
        on a native audio call: finished streams are handed to the closer thread."""
        self._prune_finished_streams()
        active_ids = set(list(self.streams.keys()))

        rms_l_pow = rms_r_pow = peak_l = peak_r = 0.0
        for sid in list(self.stream_levels):
            if sid not in active_ids:
                self.stream_levels.pop(sid, None)
                continue
            rl, rr, pl, pr = self.stream_levels[sid]
            rms_l_pow += rl ** 2
            rms_r_pow += rr ** 2
            peak_l = max(peak_l, pl)
            peak_r = max(peak_r, pr)

        return (
            min(1.0, np.sqrt(rms_l_pow)),
            min(1.0, np.sqrt(rms_r_pow)),
            min(1.0, peak_l),
            min(1.0, peak_r),
            [],  # Spectrum placeholder
        )

    def stats(self):
        return (f"streams={len(self.streams)} cached_files={len(self.cache)} "
                f"cache={self.cache.total_bytes / 1e6:.0f}MB")

    def _detach_locked(self, stream_id, s):
        """Takes a stream out of the engine's tables. Fast; safe under self.lock.
        The slow native teardown happens afterwards, in _teardown."""
        s.closed = True
        s.finished = True
        self.stream_levels.pop(stream_id, None)
        self.streams.pop(stream_id, None)
        return s

    def _teardown(self, stream_id, s):
        """Stops and closes a detached stream. These native calls can block, so
        this must never run under self.lock or on the event loop.

        abort() rather than stop(): stop() waits for queued audio to play out,
        which on some devices (virtual or multi-channel ones) can block for many
        seconds and, with several pads starting and stopping at once, hang."""
        steps = [("abort", s.stream.abort), ("close", s.stream.close)]
        if s.file is not None:
            steps.append(("file close", s.file.close))
        t0 = time.monotonic()
        with self._pa_lock:
            for step, fn in steps:
                try:
                    fn()
                except Exception as e:
                    log.warning("Stream %s %s failed: %r", stream_id, step, e)
        took = (time.monotonic() - t0) * 1000
        log.info("Stream %s cleaned up (%s) in %.0fms", stream_id, os.path.basename(s.path), took)
        if took > 1000:
            log.warning("Stream %s teardown was slow (%.0fms); the audio device is struggling", stream_id, took)

        # Always tell the app, even if the callback never got to: otherwise its
        # pad would stay stuck in the playing state.
        try:
            s.notify_finished(stream_id)
        except Exception:
            log.exception("on_finished callback failed during cleanup of stream %s", stream_id)

    def _prune_finished_streams(self):
        """Detaches streams that ended and queues their teardown (non-blocking)."""
        with self.lock:
            done = []
            for sid, s in list(self.streams.items()):
                try:
                    gone = s.finished or not s.stream.active
                except Exception:
                    gone = True
                if gone:
                    done.append((sid, self._detach_locked(sid, s)))
        for sid, s in done:
            self._closer.submit(self._teardown, sid, s)

    # ── Waveform ───────────────────────────────────────────────────────────

    def get_waveform(self, file_path, points=100):
        """Returns (normalized peak amplitudes, duration seconds). Decoding is
        shared with playback through the cache, so a pad that has a waveform is
        also ready to play instantly."""
        try:
            audio = self.cache.load(file_path)
            if audio is not None:
                return self._peaks(audio.data, points), audio.frames / audio.samplerate
            return self._waveform_streaming(file_path, points)
        except Exception:
            log.exception("Error generating waveform for %s", file_path)
            return [], 0.0

    @staticmethod
    def _peaks(data, points):
        frames = len(data)
        if frames == 0:
            return []
        block = max(1, frames // points)
        n = min(points, frames // block)
        peaks = np.abs(data[:n * block]).max(axis=1).reshape(n, block).max(axis=1)
        top = float(peaks.max())
        return (peaks / top).tolist() if top > 0 else peaks.tolist()

    def _waveform_streaming(self, file_path, points):
        """Waveform for files too large to cache: read block by block."""
        with sf.SoundFile(file_path) as f:
            if f.frames == 0:
                return [], 0.0
            block = max(1, f.frames // points)
            peaks = []
            for _ in range(points):
                data = f.read(block, dtype='float32')
                if len(data) == 0:
                    break
                peaks.append(float(np.max(np.abs(data))))
            top = max(peaks) if peaks else 0
            if top > 0:
                peaks = [v / top for v in peaks]
            return peaks, f.frames / f.samplerate

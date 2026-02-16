import sounddevice as sd
import soundfile as sf
import numpy as np
import threading
import os

class AudioEngine:
    def __init__(self):
        self.streams = {}
        self.next_stream_id = 0
        self.lock = threading.RLock()
        self.master_volume = 1.0
        # Stores current RMS/Peak per stream: { stream_id: (rms_l, rms_r, peak_l, peak_r) }
        self.stream_levels = {}
        self.last_mix = np.zeros((1024, 2))
        self.mix_lock = threading.Lock()

    def list_devices(self):
        """Returns a list of available output devices."""
        try:
            # Re-query devices to catch any hot-plugged ones
            try:
                sd._terminate()
                sd._initialize()
            except:
                pass
            devices = sd.query_devices()
            hostapis = sd.query_hostapis()
            output_devices = []
            for i, dev in enumerate(devices):
                if dev['max_output_channels'] > 0:
                    api_index = dev['hostapi']
                    api_name = hostapis[api_index]['name'] if api_index < len(hostapis) else str(api_index)
                    
                    output_devices.append({
                        "id": i,
                        "name": dev['name'],
                        "hostapi": api_name,
                        "channels": dev['max_output_channels']
                    })
            return output_devices
        except Exception as e:
            print(f"Error listing devices: {e}")
            return []

    def play(self, file_path, device_id=None, volume=1.0, loop=False, on_finished=None, output_channels=None, filter_type='none', filter_freq=20000):
        """Plays an audio file on a specific device."""
        print(f"DEBUG ENGINE: Attempting to play {file_path} on device {device_id}", flush=True)
        try:
            if not os.path.exists(file_path):
                print(f"DEBUG ENGINE ERROR: File does not exist: {file_path}", flush=True)
                raise FileNotFoundError(f"File not found: {file_path}")

            # Load file
            f = sf.SoundFile(file_path)
            print(f"DEBUG ENGINE: File opened. SR={f.samplerate}, CH={f.channels}", flush=True)
            
            # Optimization: Read entire file into memory if < 20MB
            # 20MB is roughly 2 minutes of stereo 44.1kHz 16-bit audio
            is_preloaded = False
            audio_data = None
            if f.seekable and f.frames * f.channels * 4 < 20 * 1024 * 1024:
                audio_data = f.read(dtype='float32')
                is_preloaded = True
            else:
                f.seek(0)

            stream_id = self.next_stream_id
            self.next_stream_id += 1

            # Callback context
            ctx = {
                "file": f,
                "data": audio_data,
                "is_preloaded": is_preloaded,
                "cursor": 0,
                "volume": volume,
                "loop": loop,
                "finished": False,
                "on_finished_called": False,
                "on_finished": on_finished,
                "output_channels": output_channels,
                "filter_type": filter_type,
                "filter_freq": filter_freq,
                "filter_state": None, # Will store [last_y_L, last_y_R]
                "first_frame": True
            }

            def callback(outdata, frames, time, status):
                if ctx["first_frame"]:
                    print("DEBUG ENGINE: Audio callback is alive and running", flush=True)
                    ctx["first_frame"] = False
                
                if status:
                    print(f"Audio status: {status}")
                
                if ctx["finished"]:
                    outdata.fill(0)
                    if not ctx["on_finished_called"] and ctx["on_finished"]:
                        ctx["on_finished_called"] = True
                        ctx["on_finished"]()
                    raise sd.CallbackStop

                # Initialize data_chunk as empty with correct shape
                channels_in = ctx["data"].shape[1] if ctx["is_preloaded"] and len(ctx["data"].shape) > 1 else (ctx["file"].channels if not ctx["is_preloaded"] else 1)
                data_chunk = np.zeros((0, channels_in), dtype='float32') if channels_in > 1 else np.zeros((0,), dtype='float32')
                
                while len(data_chunk) < frames:
                    needed = frames - len(data_chunk)
                    
                    if ctx["is_preloaded"]:
                        # Read from memory
                        available = len(ctx["data"]) - ctx["cursor"]
                        if available > 0:
                            take = min(available, needed)
                            chunk = ctx["data"][ctx["cursor"]:ctx["cursor"]+take]
                            if len(data_chunk) == 0:
                                data_chunk = chunk
                            else:
                                data_chunk = np.concatenate((data_chunk, chunk))
                            ctx["cursor"] += take
                        
                        if len(data_chunk) < frames:
                            if ctx["loop"]:
                                ctx["cursor"] = 0
                            else:
                                ctx["finished"] = True
                                break 
                    else:
                        # Read from disk
                        chunk = ctx["file"].read(needed, dtype='float32')
                        if len(chunk) > 0:
                            if len(data_chunk) == 0:
                                data_chunk = chunk
                            else:
                                if len(data_chunk.shape) == 1 and len(chunk.shape) == 1:
                                    data_chunk = np.concatenate((data_chunk, chunk))
                                else:
                                    if len(data_chunk.shape) == 1:
                                        data_chunk = data_chunk.reshape(-1, 1)
                                    if len(chunk.shape) == 1:
                                        chunk = chunk.reshape(-1, 1)
                                    data_chunk = np.vstack((data_chunk, chunk))
                        
                        if len(data_chunk) < frames:
                            if ctx["loop"]:
                                ctx["file"].seek(0)
                            else:
                                ctx["finished"] = True
                                break
                
                # Apply volume
                if len(data_chunk) > 0:
                    data_chunk *= (ctx["volume"] * self.master_volume)

                # Assign to outdata with channel handling
                outdata.fill(0) 

                if len(data_chunk) > 0:
                    write_len = len(data_chunk)
                    if write_len > len(outdata):
                         write_len = len(outdata)
                         data_chunk = data_chunk[:write_len]

                    curr_channels_in = 1 if len(data_chunk.shape) == 1 else data_chunk.shape[1]
                    
                    targets = ctx["output_channels"]
                    if targets is None:
                        channels_out = outdata.shape[1]
                        if curr_channels_in == 1 and channels_out >= 2:
                             outdata[:write_len, 0] = data_chunk.flatten()
                             outdata[:write_len, 1] = data_chunk.flatten()
                        elif curr_channels_in == channels_out:
                             outdata[:write_len] = data_chunk
                        else:
                             min_ch = min(curr_channels_in, channels_out)
                             if len(data_chunk.shape) == 1:
                                  outdata[:write_len, 0] = data_chunk
                             else:
                                  outdata[:write_len, :min_ch] = data_chunk[:, :min_ch]
                    else:
                        if len(data_chunk.shape) == 1:
                            data_chunk = data_chunk.reshape(-1, 1)
                        
                        curr_channels_in = data_chunk.shape[1]
                        for i, target_ch in enumerate(targets):
                            if target_ch < outdata.shape[1]:
                                source_ch = i % curr_channels_in
                                outdata[:write_len, target_ch] = data_chunk[:, source_ch]

                    # --- Master Soft Limiter ---
                    # Prevents harsh digital clipping by squashing peaks near 1.0
                    # Using tanh for a soft-knee limit
                    np.tanh(outdata[:write_len], out=outdata[:write_len]) 
                    
                    # --- Metering Calculation (Post-Routing, Post-Limiting) ---
                    # Calculate RMS and Peak for hardware channels 0 and 1
                    # This ensures the meter matches what the user actually hears on L/R
                    meter_data = outdata[:write_len]
                    peaks = np.max(np.abs(meter_data), axis=0)
                    rms_vals = np.sqrt(np.mean(meter_data**2, axis=0))

                    pl = float(peaks[0]) if len(peaks) > 0 else 0.0
                    pr = float(peaks[1]) if len(peaks) > 1 else 0.0
                    rl = float(rms_vals[0]) if len(rms_vals) > 0 else 0.0
                    rr = float(rms_vals[1]) if len(rms_vals) > 1 else 0.0
                    
                    self.stream_levels[stream_id] = (rl, rr, pl, pr)

                    # Store a copy of the final mixed outdata for spectrum analysis
                    if write_len == 1024:
                        with self.mix_lock:
                            self.last_mix = outdata.copy()

                    if write_len < len(outdata) and ctx["finished"]:
                        if not ctx["on_finished_called"] and ctx["on_finished"]:
                            ctx["on_finished_called"] = True
                            ctx["on_finished"]()
                        raise sd.CallbackStop
                else:
                    self.stream_levels[stream_id] = (0.0, 0.0, 0.0, 0.0)
                    if ctx["finished"]:
                        if not ctx["on_finished_called"] and ctx["on_finished"]:
                            ctx["on_finished_called"] = True
                            ctx["on_finished"]()
                        raise sd.CallbackStop

            # Determine device max channels
            try:
                device_info = sd.query_devices(device_id, 'output')
                max_ch = device_info['max_output_channels']
            except Exception as e:
                print(f"DEBUG ENGINE: Invalid device_id {device_id}, falling back to default. Error: {e}", flush=True)
                device_id = None # Fallback to default
                try:
                    device_info = sd.query_devices(None, 'output')
                    max_ch = device_info['max_output_channels']
                except:
                    max_ch = 2

            try:
                stream = sd.OutputStream(
                    device=device_id,
                    samplerate=f.samplerate,
                    channels=max_ch, # Always open all channels
                    callback=callback,
                    latency='low', 
                    blocksize=1024 
                )
                stream.start()
            except Exception as e:
                if device_id is not None:
                    print(f"DEBUG ENGINE: Failed to start stream on device {device_id}, retrying on default device. Error: {e}", flush=True)
                    stream = sd.OutputStream(
                        device=None,
                        samplerate=f.samplerate,
                        channels=2, 
                        callback=callback,
                        latency='low', 
                        blocksize=1024 
                    )
                    stream.start()
                else:
                    raise e

            with self.lock:
                self.streams[stream_id] = {
                    "stream": stream,
                    "ctx": ctx,
                    "path": file_path
                }
            
            duration = f.frames / f.samplerate
            return stream_id, duration

        except Exception as e:
            print(f"Error starting playback: {e}")
            raise e

    def stop(self, stream_id):
        with self.lock:
            if stream_id in self.streams:
                s = self.streams[stream_id]
                try:
                    s["stream"].stop()
                    s["stream"].close()
                    if not s["ctx"]["is_preloaded"]:
                        s["ctx"]["file"].close()
                except Exception as e:
                    print(f"Error stopping stream {stream_id}: {e}")
                del self.streams[stream_id]

    def stop_all(self):
        with self.lock:
            ids = list(self.streams.keys())
            for sid in ids:
                self.stop(sid)

    def set_master_volume(self, volume):
        with self.lock:
            self.master_volume = max(0.0, min(1.0, volume))

    def get_levels(self):
        """Returns aggregated Master Levels and a 16-band spectrum."""
        with self.lock:
            active_ids = list(self.streams.keys())
        
        rms_l_pow = 0.0
        rms_r_pow = 0.0
        peak_l_max = 0.0
        peak_r_max = 0.0
        
        to_remove = []
        for sid, levels in list(self.stream_levels.items()):
            if sid not in active_ids:
                to_remove.append(sid)
                continue
            
            rl, rr, pl, pr = levels
            # Sum of powers for RMS
            rms_l_pow += rl**2
            rms_r_pow += rr**2
            # Max for Peaks
            peak_l_max = max(peak_l_max, pl)
            peak_r_max = max(peak_r_max, pr)

        for sid in to_remove:
            del self.stream_levels[sid]
            
        return (
            min(1.0, np.sqrt(rms_l_pow)),
            min(1.0, np.sqrt(rms_r_pow)),
            min(1.0, peak_l_max),
            min(1.0, peak_r_max),
            [] # Spectrum placeholder
        )

    def set_volume(self, stream_id, volume):
        with self.lock:
            if stream_id in self.streams:
                self.streams[stream_id]["ctx"]["volume"] = volume

    def set_looping(self, stream_id, loop):
        with self.lock:
            if stream_id in self.streams:
                self.streams[stream_id]["ctx"]["loop"] = loop

    def set_routing(self, stream_id, output_channels):
        with self.lock:
            if stream_id in self.streams:
                self.streams[stream_id]["ctx"]["output_channels"] = output_channels

    def set_filter(self, stream_id, filter_type, freq):
        """Updates filter parameters for a stream."""
        with self.lock:
            if stream_id in self.streams:
                ctx = self.streams[stream_id]["ctx"]
                ctx["filter_type"] = filter_type
                ctx["filter_freq"] = freq

    def seek(self, stream_id, position_seconds):
        """Seeks to a specific position in seconds."""
        with self.lock:
            if stream_id in self.streams:
                s = self.streams[stream_id]
                ctx = s["ctx"]
                f = ctx["file"]
                
                # Calculate frame position
                target_frame = int(position_seconds * f.samplerate)
                
                if ctx["is_preloaded"]:
                    # Clamp to buffer size
                    ctx["cursor"] = max(0, min(target_frame, len(ctx["data"])))
                else:
                    # Seek file pointer
                    f.seek(max(0, min(target_frame, f.frames)))
                
                # If it was finished, we might need to reset finished flag?
                # But usually seek happens while playing or paused.
                # If it stopped, the stream might be closed already.
                ctx["finished"] = False

    def get_waveform(self, file_path, points=100):
        """Generates a simplified waveform for visualization."""
        try:
            # Read file with soundfile
            # Always read as mono for visualization to keep it simple
            # If stereo, we can average channels or take max.
            # Using soundfile directly to avoid overhead if not preloaded.
            
            with sf.SoundFile(file_path) as f:
                frames = f.frames
                if frames == 0:
                    return []
                
                # Determine chunk size to get approx 'points' data points
                step = max(1, frames // points)
                
                # Read entire file into numpy array (if it fits in memory)
                # For visualization, we might not need high precision.
                # Reading whole file is fastest for numpy operations if size permits.
                # 50MB file is fine. 500MB might be slow. 
                # Let's try block reading for safety if file is huge, but for now
                # let's assume reasonable sample sizes (< 5 mins).
                
                # Optimized approach: read the whole file, but if it's too large,
                # we might want to read strided. 
                # soundfile doesn't support strided read easily without reading blocks.
                
                # Let's read the whole file if < 10 minutes (approx 100MB @ 44.1/16/stereo).
                # Actually, reading into float32 takes 4x space. 
                # 1 min stereo = 10MB float32.
                # 10 mins = 100MB. This is fine for desktop.
                
                data = f.read(dtype='float32')
                
                # Convert to mono if needed
                if len(data.shape) > 1:
                    # Average channels
                    data = np.mean(data, axis=1)
                
                # Decimate / Resample
                # Simple peak detection in chunks is better than just taking every Nth sample
                # because we want to see transients.
                # But calculating max of every chunk in python loop is slow.
                # Numpy reshape trick:
                
                # Trim to multiple of 'points'
                n_samples = len(data)
                n_chunks = points
                chunk_size = n_samples // n_chunks
                
                if chunk_size < 1:
                    return data.tolist() # return all points if fewer than requested
                
                # Crop end
                data = data[:n_chunks * chunk_size]
                
                # Reshape to (points, chunk_size)
                reshaped = data.reshape(n_chunks, chunk_size)
                
                # Take absolute max of each chunk
                waveform = np.max(np.abs(reshaped), axis=1)
                
                # Normalize (optional, but good for UI)
                peak = np.max(waveform)
                if peak > 0:
                    waveform /= peak
                
                duration = frames / f.samplerate
                return waveform.tolist(), duration

        except Exception as e:
            print(f"Error generating waveform: {e}")
            return [], 0.0

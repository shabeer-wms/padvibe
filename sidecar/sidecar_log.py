"""Logging for the sidecar.

Everything goes through the stdlib `logging` module with one format, to:
  * stdout  (INFO and up; the Flutter app captures it into its own log file)
  * a rotating file in $PADVIBE_LOG_DIR (everything, DEBUG and up), which
    survives even if the app dies
and native crashes (SIGSEGV, SIGABRT, ...) are written as Python tracebacks to
sidecar_crash.log via faulthandler. A watchdog thread dumps all thread stacks
if the asyncio loop stops responding, which shows where a hang is.
"""
import atexit
import faulthandler
import logging
import logging.handlers
import os
import signal
import sys
import threading
import time

FORMAT = "%(asctime)s.%(msecs)03d [%(levelname)s] [%(threadName)s] %(name)s: %(message)s"
DATEFMT = "%Y-%m-%dT%H:%M:%S"

log = logging.getLogger("sidecar")

_crash_file = None
_last_tick = time.monotonic()
_stats_provider = None


def setup():
    """Configures logging; safe to call once at process start."""
    global _crash_file
    log.setLevel(logging.DEBUG)
    formatter = logging.Formatter(FORMAT, DATEFMT)

    out = logging.StreamHandler(sys.stdout)
    out.setLevel(logging.INFO)
    out.setFormatter(formatter)
    log.addHandler(out)

    log_dir = os.environ.get("PADVIBE_LOG_DIR")
    if log_dir:
        try:
            os.makedirs(log_dir, exist_ok=True)
            fh = logging.handlers.RotatingFileHandler(
                os.path.join(log_dir, "sidecar_engine.log"),
                maxBytes=10 * 1024 * 1024,
                backupCount=5,
                encoding="utf-8",
            )
            fh.setLevel(logging.DEBUG)
            fh.setFormatter(formatter)
            log.addHandler(fh)
            _crash_file = open(os.path.join(log_dir, "sidecar_crash.log"), "a", buffering=1)
            _crash_file.write(f"\n===== sidecar pid {os.getpid()} started {time.ctime()} =====\n")
            faulthandler.enable(file=_crash_file, all_threads=True)
        except Exception as e:  # logging must never stop the sidecar from starting
            log.warning("File logging unavailable: %s", e)
    if _crash_file is None:
        faulthandler.enable(all_threads=True)  # stderr, captured by the app

    sys.excepthook = lambda t, v, tb: log.critical("Uncaught exception", exc_info=(t, v, tb))
    threading.excepthook = lambda a: log.critical(
        "Uncaught exception in thread %s", a.thread.name if a.thread else "?",
        exc_info=(a.exc_type, a.exc_value, a.exc_traceback),
    )
    atexit.register(lambda: log.info("Sidecar process exiting (atexit)"))

    log.info(
        "Sidecar starting: pid=%s ppid=%s python=%s platform=%s frozen=%s parent_env=%s",
        os.getpid(), os.getppid(), sys.version.split()[0], sys.platform,
        getattr(sys, "frozen", False), os.environ.get("PADVIBE_PARENT_PID"),
    )


def install_signal_logging(on_exit):
    """Logs termination signals, then runs on_exit() (cleanup) and exits."""
    def handler(signum, _frame):
        log.warning("Received signal %s (%s); shutting down", signum, signal.Signals(signum).name)
        try:
            on_exit()
        finally:
            os._exit(0)

    for name in ("SIGTERM", "SIGHUP", "SIGINT"):
        sig = getattr(signal, name, None)
        if sig is not None:
            try:
                signal.signal(sig, handler)
            except (ValueError, OSError):  # not main thread / unsupported
                pass


def tick():
    """Called from the asyncio loop every second to show it is alive."""
    global _last_tick
    _last_tick = time.monotonic()


def start_monitor(stats_provider, hang_after=10.0, heartbeat_every=60.0):
    """Starts a thread that logs periodic stats and dumps all stacks on a hang."""
    global _stats_provider
    _stats_provider = stats_provider

    def run():
        last_beat = time.monotonic()
        dumped = False
        while True:
            time.sleep(1)
            now = time.monotonic()
            lag = now - _last_tick
            if lag > hang_after and not dumped:
                dumped = True
                log.error("Event loop unresponsive for %.1fs; dumping all thread stacks to crash log", lag)
                if _crash_file:
                    _crash_file.write(f"\n--- loop hang {time.ctime()} (lag {lag:.1f}s) ---\n")
                faulthandler.dump_traceback(file=_crash_file or sys.stderr, all_threads=True)
            elif lag <= hang_after and dumped:
                dumped = False
                log.warning("Event loop responsive again after hang")
            if now - last_beat >= heartbeat_every:
                last_beat = now
                log.info("Heartbeat: %s", describe_stats())

    threading.Thread(target=run, name="monitor", daemon=True).start()


def describe_stats():
    parts = []
    try:
        import resource
        rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        rss_mb = rss / (1024 * 1024) if sys.platform == "darwin" else rss / 1024
        parts.append(f"max_rss={rss_mb:.0f}MB")
    except Exception:
        pass
    parts.append(f"threads={threading.active_count()}")
    if _stats_provider:
        try:
            parts.append(_stats_provider())
        except Exception as e:
            parts.append(f"stats_error={e}")
    return " ".join(parts)

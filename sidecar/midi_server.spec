# -*- mode: python ; coding: utf-8 -*-
#
# One-dir build of the sidecar. Used on every OS:
#   pyinstaller --noconfirm --distpath sidecar/dist --workpath build/sidecar sidecar/midi_server.spec
#
# Why one-dir: a one-file build re-extracts itself into a fresh temp directory
# on every launch and macOS re-scans all of it each time (~13s measured, versus
# <1s for a one-dir build after its first run).
import glob
import os
import sys

# On Linux sounddevice loads the system libportaudio via ctypes, which
# PyInstaller cannot see, so bundle it. (macOS/Windows wheels ship their own.)
binaries = []
if sys.platform.startswith('linux'):
    for pattern in ('/usr/lib/*/libportaudio.so.2', '/usr/lib64/libportaudio.so.2', '/usr/lib/libportaudio.so.2'):
        found = glob.glob(pattern)
        if found:
            binaries.append((found[0], '.'))
            break
    else:
        raise SystemExit('libportaudio.so.2 not found - install libportaudio2 before building the sidecar')

a = Analysis(
    [os.path.join(SPECPATH, 'midi_server.py')],
    pathex=[SPECPATH],
    binaries=binaries,
    datas=[],
    hiddenimports=['mido.backends.rtmidi'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    # Never imported by the sidecar; setuptools alone cost ~6s of cold import time.
    excludes=['setuptools', 'pkg_resources', 'distutils', '_distutils_hack', 'pydoc', 'tkinter'],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='midi_server',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,  # UPX breaks macOS signatures and triggers Windows AV false positives
    console=True,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    name='midi_server',
)

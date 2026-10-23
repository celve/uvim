#!/usr/bin/env python3
"""Run Sparkle for one staged ZIP, then remove only this invocation's extracts."""

import ctypes
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time


ARCHIVES = {"zip", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz", "lzma", "dmg", "aar", "yaa"}
STATE = ".uvim-appcast-v1"
requested_signal = 0


def native_cache():
    foundation = ctypes.CDLL("/System/Library/Frameworks/Foundation.framework/Foundation")
    objc = ctypes.CDLL("/usr/lib/libobjc.A.dylib")
    objc.sel_registerName.argtypes = [ctypes.c_char_p]
    objc.sel_registerName.restype = ctypes.c_void_p
    search = foundation.NSSearchPathForDirectoriesInDomains
    search.argtypes = [ctypes.c_ulong, ctypes.c_ulong, ctypes.c_bool]
    search.restype = ctypes.c_void_p
    send = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)(("objc_msgSend", objc))
    utf8 = ctypes.CFUNCTYPE(ctypes.c_char_p, ctypes.c_void_p, ctypes.c_void_p)(("objc_msgSend", objc))
    # Sparkle uses Foundation's user caches directory, independently of TMPDIR and HOME.
    paths = search(13, 1, True)
    path = send(paths, objc.sel_registerName(b"firstObject"))
    return Path(os.fsdecode(utf8(path, objc.sel_registerName(b"UTF8String")))) / "Sparkle_generate_appcast"


def interrupted(signum, _frame):
    global requested_signal
    requested_signal = requested_signal or signum


def check_signal():
    if requested_signal:
        raise InterruptedError("appcast generation interrupted")


def save_manifest(state, manifest):
    with (state / "run.json.new").open("w") as out:
        json.dump(manifest, out)
        out.flush()
        os.fsync(out.fileno())
    os.replace(state / "run.json.new", state / "run.json")


def group_alive(pgid):
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return False
    # Orphaned zombies cannot write and may await reaping by launchd after a killed caller.
    rows = subprocess.check_output(["/bin/ps", "-axo", "pgid=,stat="], text=True)
    return any(int(group) == pgid and not status.startswith("Z")
               for group, status in (row.split() for row in rows.splitlines() if row.strip()))


def signal_group(pgid, signum):
    try:
        os.killpg(pgid, signum)
    except ProcessLookupError:
        pass


def finish_child(child, stop=0):
    sent_at = None
    while True:
        status = child.poll()
        if status is not None and not group_alive(child.pid):
            return 128 + requested_signal if requested_signal else (status if status >= 0 else 128 - status)
        if sent_at is None and (stop or requested_signal or (status is not None and status != 0)):
            signal_group(child.pid, stop or requested_signal or signal.SIGTERM)
            sent_at = time.monotonic()
        if sent_at is not None and time.monotonic() - sent_at >= 5:
            signal_group(child.pid, signal.SIGKILL)
        time.sleep(0.05)


def remove_owned(cache, state, manifest):
    identity = cache.stat()
    if not isinstance(manifest, dict) or manifest.get("version") != 1 or manifest.get("cache") != [identity.st_dev, identity.st_ino]:
        raise RuntimeError("cache identity changed; retaining ownership manifest")
    owned = manifest.get("owned")
    pgid = manifest.get("pgid")
    if (not isinstance(owned, list) or any(not isinstance(name, str) or
            not re.fullmatch(r"[0-9a-f]{64}(?:\.tmp)?", name) for name in owned) or
            (pgid is not None and (type(pgid) is not int or pgid <= 1))):
        raise RuntimeError("invalid ownership manifest; refusing cleanup")
    while pgid is not None and group_alive(pgid):
        check_signal()
        time.sleep(0.05)
    for name in owned:
        path = cache / name
        if path.is_symlink() or path.is_file():
            path.unlink()
        elif path.exists():
            shutil.rmtree(path)
    (state / "run.json").unlink()


def archive_hash(directory):
    archives = [p for p in directory.iterdir() if not p.name.startswith(".") and
                p.suffix[1:] in ARCHIVES and not p.is_dir()]
    # The release and update probes stage one ZIP; wider feeds have Sparkle pruning semantics of their own.
    if (len(archives) != 1 or archives[0].suffix != ".zip" or
            archives[0].is_symlink() or not archives[0].is_file()):
        raise RuntimeError("stage exactly one regular ZIP for appcast generation")
    digest = hashlib.sha256()
    with archives[0].open("rb") as archive:
        for chunk in iter(lambda: archive.read(1024 * 1024), b""):
            check_signal()
            digest.update(chunk)
    return digest.hexdigest()


def generate(cache, generator, arguments):
    cache.mkdir(parents=True, exist_ok=True)
    cache = cache.resolve()
    state = cache / STATE
    state.mkdir(mode=0o700, exist_ok=True)
    if state.is_symlink() or state.stat().st_uid != os.getuid():
        raise RuntimeError("ownership directory is not a private local directory")
    with os.fdopen(os.open(state / "lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600), "r+") as lock:
        # Keep a single lock inode: unlinking a flock file would let two callers hold different locks.
        while True:
            check_signal()
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                time.sleep(0.05)
        if (state / "run.json").exists():
            manifest = json.loads((state / "run.json").read_text())
            remove_owned(cache, state, manifest)
            print("Recovered abandoned Sparkle extraction ownership.", file=sys.stderr)
        check_signal()
        digest = archive_hash(Path(arguments[-1]))
        names = [digest, digest + ".tmp"]
        if (cache / names[1]).exists() or (cache / names[1]).is_symlink():
            raise RuntimeError("pre-existing Sparkle temporary extraction; refusing to overwrite it")
        if (cache / digest).is_symlink():
            raise RuntimeError("pre-existing Sparkle extraction symlink; refusing to use it")
        owned = [name for name in names if not os.path.lexists(cache / name)]
        identity = cache.stat()
        manifest = {"version": 1, "cache": [identity.st_dev, identity.st_ino], "owned": owned, "pgid": None}
        save_manifest(state, manifest)
        child = None
        gate_read, gate_write = os.pipe()
        try:
            # The child cannot extract until its process group is durably recorded for SIGKILL recovery.
            child = subprocess.Popen(
                [sys.executable, str(Path(__file__).resolve()), "--child", str(gate_read), generator, *arguments],
                start_new_session=True, pass_fds=(gate_read, lock.fileno()))
            os.close(gate_read)
            gate_read = None
            manifest["pgid"] = child.pid
            save_manifest(state, manifest)
            if not requested_signal:
                os.write(gate_write, b"1")
            os.close(gate_write)
            gate_write = None
            status = finish_child(child)
        finally:
            if gate_read is not None:
                os.close(gate_read)
            if gate_write is not None:
                os.close(gate_write)
            if child is not None:
                finish_child(child, signal.SIGTERM)
            remove_owned(cache, state, manifest)
        return status


def main(arguments):
    for signum in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, interrupted)
    try:
        if len(arguments) < 2 or not Path(arguments[-1]).is_dir():
            raise RuntimeError("usage: generate-appcast.py GENERATOR [OPTIONS...] ARCHIVES_DIR")
        generator = str(Path(arguments[0]).resolve())
        if not os.access(generator, os.X_OK):
            raise RuntimeError("generate_appcast is not executable: " + generator)
        return generate(native_cache(), generator, arguments[1:])
    except (OSError, ValueError, RuntimeError) as error:
        print("error: " + str(error), file=sys.stderr)
        return 128 + requested_signal if requested_signal else 1


if __name__ == "__main__":
    if sys.argv[1:2] == ["--child"]:
        gate = int(sys.argv[2])
        ready = os.read(gate, 1)
        os.close(gate)
        if ready == b"1":
            os.execv(sys.argv[3], sys.argv[3:])
        sys.exit(1)
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Validate extraction ownership with the real Sparkle tools; keep fixtures and logs in WORK."""

import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import time

from test_generate_appcast import WRAPPER, STATE, load_wrapper


def snapshot(cache):
    result = {}
    for top in cache.iterdir():
        if top.name == STATE:
            continue
        for path in [top, *(top.rglob("*") if top.is_dir() and not top.is_symlink() else [])]:
            stat = path.lstat()
            result[str(path.relative_to(cache))] = [stat.st_mode, stat.st_size, stat.st_mtime_ns, stat.st_blocks]
    return result


def main():
    bin_dir, work = (Path(arg).resolve() for arg in sys.argv[1:])
    work.mkdir(parents=True, exist_ok=False)
    module = load_wrapper(WRAPPER)
    cache = module.native_cache()
    cache.mkdir(parents=True, exist_ok=True)
    original = snapshot(cache)
    print("native cache:", cache, "->", cache.resolve(), flush=True)
    print("generator sha256:", hashlib.sha256((bin_dir / "generate_appcast").read_bytes()).hexdigest(), flush=True)
    print("cache device:", cache.stat().st_dev, "work device:", work.stat().st_dev, flush=True)
    swift = work / "public-keys.swift"
    swift.write_text('''import CryptoKit
import Foundation
for path in CommandLine.arguments.dropFirst() {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    let seed = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines))!
    print(try Curve25519.Signing.PrivateKey(rawRepresentation: seed).publicKey.rawRepresentation.base64EncodedString())
}
''')
    keys = [work / (str(index) + ".key") for index in range(18)]
    for key in keys:
        key.write_bytes(base64.b64encode(os.urandom(32)) + b"\n")
        key.chmod(0o600)
    pubs = subprocess.check_output(["/usr/bin/xcrun", "swift", str(swift), *map(str, keys)], text=True).splitlines()
    cases = []
    for index, (key, pub) in enumerate(zip(keys, pubs)):
        stage = work / ("case-" + str(index))
        stage.mkdir()
        app = work / ("app-" + str(index)) / "UpdateProbe.app"
        (app / "Contents/MacOS").mkdir(parents=True)
        shutil.copy("/usr/bin/true", app / "Contents/MacOS/UpdateProbe")
        info = dict(CFBundleIdentifier="com.loom.sparkle-cache-probe", CFBundleExecutable="UpdateProbe",
                    CFBundleName="UpdateProbe", CFBundlePackageType="APPL", CFBundleVersion=str(index + 1),
                    CFBundleShortVersionString="1.0", LSMinimumSystemVersion="14.0", SUPublicEDKey=pub,
                    SUFeedURL="https://example.invalid/appcast.xml")
        with (app / "Contents/Info.plist").open("wb") as out:
            plistlib.dump(info, out)
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
        archive = stage / "UpdateProbe.zip"
        subprocess.run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive)], check=True)
        (stage / "UpdateProbe.md").write_text("Owned cache validation " + str(index))
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        cases.append((stage, key, digest))
    sentinel = cache / hashlib.sha256(os.urandom(32)).hexdigest()
    sentinel.mkdir()
    (sentinel / "sentinel").write_text("pre-existing unrelated extraction")
    matching = cache / cases[0][2]
    if matching.exists():
        raise RuntimeError("fixture unexpectedly matches an existing cache entry")
    subprocess.run(["/usr/bin/ditto", "-x", "-k", str(cases[0][0] / "UpdateProbe.zip"), str(matching)], check=True)
    (matching / "sentinel").write_text("pre-existing matching extraction")
    baseline = snapshot(cache)
    (work / "baseline.json").write_text(json.dumps(baseline, indent=2) + "\n")
    peak = 0

    def launch(case, key=None):
        stage, own_key, digest = case
        log = (stage / "generator.log").open("w")
        arguments = [sys.executable, str(WRAPPER), str(bin_dir / "generate_appcast"),
                     "--ed-key-file", str(key or own_key), "--download-url-prefix", "https://example.invalid/",
                     "--embed-release-notes", "-o", str(stage / "appcast.xml"), str(stage)]
        child = subprocess.Popen(arguments, stdout=log, stderr=subprocess.STDOUT)
        return child, log, case

    def complete(runs, signed=True, status=0):
        nonlocal peak
        while any(child.poll() is None for child, _, _ in runs):
            peak = max(peak, sum(1 for path in cache.iterdir() if re.fullmatch(r"[0-9a-f]{64}(?:\.tmp)?", path.name)
                                 and path.name not in {sentinel.name, matching.name}))
            time.sleep(0.01)
        for child, log, (stage, key, digest) in runs:
            log.close()
            if child.returncode != status:
                raise AssertionError(str(stage) + ": " + (stage / "generator.log").read_text())
            if signed:
                signature = re.search(r'sparkle:edSignature="([^"]+)"', (stage / "appcast.xml").read_text()).group(1)
                subprocess.run([str(bin_dir / "sign_update"), "--verify", "--ed-key-file", str(key),
                                str(stage / "UpdateProbe.zip"), signature], check=True, capture_output=True)
            if snapshot(cache) != baseline or (cache / STATE / "run.json").exists():
                raise AssertionError("cache did not return to its exact baseline")
        print("passed:", [case[0].name for _, _, case in runs], "expected status", status, flush=True)

    for case in cases[:10]:
        complete([launch(case)])
    complete([launch(case) for case in cases[10:16]])
    complete([launch(cases[16], key=keys[17])], signed=False)
    if 'sparkle:edSignature=' in (cases[16][0] / "appcast.xml").read_text():
        raise AssertionError("wrong-key fixture unexpectedly signed")
    (cases[17][0] / "UpdateProbe.zip").write_bytes(b"invalid zip")
    complete([launch(cases[17])], signed=False, status=1)
    shutil.rmtree(matching)
    shutil.rmtree(sentinel)
    if snapshot(cache) != original:
        raise AssertionError("validation changed pre-existing entries")
    for key in keys:
        key.unlink()
    (work / "result.json").write_text(json.dumps(dict(repeated=10, concurrent=6, wrong_key=1, invalid_zip=1,
                                                      peak_new_hash_paths=peak, baseline_restored=True), indent=2) + "\n")
    print("baseline restored; peak new hash paths:", peak, flush=True)


if __name__ == "__main__":
    main()

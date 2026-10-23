#!/usr/bin/env python3
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest


WRAPPER = Path(__file__).resolve().parents[1] / "generate-appcast.py"
STATE = ".uvim-appcast-v1"
FAKE = r'''#!/usr/bin/env python3
import hashlib, os, pathlib, signal, subprocess, sys, time
cache = pathlib.Path(os.environ["FAKE_CACHE"])
evidence = pathlib.Path(os.environ["EVIDENCE"])
archive = next(pathlib.Path(sys.argv[-1]).glob("*.zip"))
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
final, temp = cache / digest, cache / (digest + ".tmp")
marker = cache / ".active-generator"
if marker.exists():
    (evidence / "overlap").touch()
marker.touch()
temp.mkdir(exist_ok=True)
(temp / "partial").write_text("extract")
mode = os.environ.get("MODE", "ok")
if mode in ("descendant", "failure-descendant", "stubborn"):
    code = """
import os, pathlib, signal, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
signal.signal(signal.SIGINT, signal.SIG_IGN)
(pathlib.Path(os.environ['EVIDENCE']) / 'child-ready').touch()
time.sleep(1)
temp = pathlib.Path(os.environ['CHILD_TEMP'])
evidence = pathlib.Path(os.environ['EVIDENCE'])
(evidence / 'child-saw-extraction').write_text(str(temp.exists()))
(temp / 'late-write').write_text('finished')
"""
    subprocess.Popen([sys.executable, "-c", code], env=dict(os.environ, CHILD_TEMP=str(temp)))
    while not (evidence / "child-ready").exists():
        time.sleep(0.01)
if mode == "stubborn":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
(evidence / "ready").write_text(str(os.getpid()))
if mode in ("hold", "descendant", "stubborn"):
    time.sleep(30)
else:
    time.sleep(0.15)
if mode in ("fail", "failure-descendant"):
    marker.unlink()
    sys.exit(23)
if not final.exists():
    temp.rename(final)
else:
    shutil = __import__('shutil')
    shutil.rmtree(temp)
(pathlib.Path(sys.argv[-1]) / "appcast.xml").write_text("signed appcast")
marker.unlink()
'''


def load_wrapper(path):
    spec = importlib.util.spec_from_file_location("appcast_wrapper", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ExtractionOwnershipTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="appcast-owner-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.cache = self.root / "cache"
        self.cache.mkdir()
        self.tool = self.root / "generate_appcast"
        self.tool.write_text(FAKE.replace("#!/usr/bin/env python3", "#!" + sys.executable, 1))
        self.tool.chmod(0o755)
        self.stage = self.root / "archives with spaces"
        self.stage.mkdir()
        self.archive = self.stage / "update.zip"
        self.archive.write_bytes(b"one archive")
        self.digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.sentinel = self.cache / ("a" * 64)
        self.sentinel.mkdir()
        (self.sentinel / "keep").write_bytes(b"pre-existing extraction")
        self.counter = 0
        self.children = []
        self.addCleanup(self.stop_children)

    def stop_children(self):
        manifest = self.cache / STATE / "run.json"
        if manifest.exists():
            pgid = json.loads(manifest.read_text()).get("pgid")
            if pgid:
                try:
                    os.killpg(pgid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        for child in self.children:
            if child.poll() is None:
                child.kill()
                child.wait()
            child.stdout.close()
            child.stderr.close()

    def killed(self, child):
        child.kill()
        child.wait()
        child.stdout.close()
        child.stderr.close()

    def launch(self, mode="ok", wrapper=WRAPPER, stage=None):
        self.counter += 1
        evidence = self.root / ("evidence-" + str(self.counter))
        evidence.mkdir()
        env = dict(os.environ, FAKE_CACHE=str(self.cache), EVIDENCE=str(evidence), MODE=mode)
        child = subprocess.Popen([sys.executable, __file__, "--launch", str(wrapper), str(self.cache),
                                  str(self.tool), "--some-option", "value with spaces", str(stage or self.stage)],
                                 env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.children.append(child)
        return child, evidence

    def completed(self, child, code=0):
        stdout, stderr = child.communicate(timeout=60)
        self.assertEqual(child.returncode, code, stdout + stderr)
        return stderr

    def wait_file(self, file):
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            if file.exists():
                return file.read_text()
            time.sleep(0.02)
        self.fail("process never reached " + str(file))

    def ready(self, evidence):
        return int(self.wait_file(evidence / "ready"))

    def bounded(self, extras=()):
        self.assertEqual(sorted(p.name for p in self.cache.iterdir() if not p.name.startswith(".")),
                         sorted([self.sentinel.name, *extras]))
        self.assertEqual((self.sentinel / "keep").read_bytes(), b"pre-existing extraction")
        self.assertFalse((self.cache / STATE / "run.json").exists())
        self.assertTrue(self.archive.exists())

    def test_repeated_fresh_archives_preserve_artifacts_and_baseline(self):
        for index in range(10):
            self.archive.write_bytes(str(index).encode())
            child, _ = self.launch()
            self.completed(child)
            self.bounded()
            self.assertEqual((self.stage / "appcast.xml").read_text(), "signed appcast")
        self.assertEqual(sorted(p.name for p in (self.cache / STATE).iterdir()), ["lock"])

    def test_pre_existing_matching_extract_survives(self):
        existing = self.cache / self.digest
        existing.mkdir()
        (existing / "keep").write_text("reused")
        child, _ = self.launch()
        self.completed(child)
        self.bounded([self.digest])
        self.assertEqual((existing / "keep").read_text(), "reused")

    def test_pre_existing_temporary_extract_is_preserved_and_refused(self):
        existing = self.cache / (self.digest + ".tmp")
        existing.mkdir()
        (existing / "keep").write_text("not owned")
        child, evidence = self.launch()
        self.assertIn("pre-existing", self.completed(child, 1))
        self.assertFalse((evidence / "ready").exists())
        self.bounded([existing.name])
        self.assertEqual((existing / "keep").read_text(), "not owned")

    def test_failure_cleans_partial_extract_and_preserves_exit_status(self):
        child, _ = self.launch("fail")
        self.completed(child, 23)
        self.bounded()

    def test_concurrent_callers_across_script_copies_serialize(self):
        copy = self.root / "other-checkout.py"
        shutil.copy(WRAPPER, copy)
        runs = [self.launch(wrapper=WRAPPER if i % 2 else copy) for i in range(6)]
        for child, evidence in runs:
            self.completed(child)
            self.assertFalse((evidence / "overlap").exists())
        self.bounded()

    def test_term_joins_descendant_that_outlives_generator(self):
        child, evidence = self.launch("descendant")
        self.ready(evidence)
        time.sleep(0.15)
        child.terminate()
        self.completed(child, 143)
        self.assertEqual((evidence / "child-saw-extraction").read_text(), "True")
        self.bounded()

    def test_failure_joins_descendant_that_outlives_generator(self):
        child, evidence = self.launch("failure-descendant")
        self.completed(child, 23)
        self.assertEqual((evidence / "child-saw-extraction").read_text(), "True")
        self.bounded()

    def test_term_escalates_for_stubborn_generator(self):
        child, evidence = self.launch("stubborn")
        self.ready(evidence)
        time.sleep(0.15)
        child.terminate()
        self.completed(child, 143)
        self.bounded()

    def test_sigkill_recovers_only_after_orphaned_generator_finishes(self):
        child, evidence = self.launch("descendant")
        generator = self.ready(evidence)
        time.sleep(0.15)
        self.killed(child)
        successor, next_evidence = self.launch()
        time.sleep(0.2)
        self.assertFalse((next_evidence / "ready").exists())
        os.kill(generator, signal.SIGTERM)
        self.assertIn("Recovered abandoned", self.completed(successor))
        self.assertEqual((evidence / "child-saw-extraction").read_text(), "True")
        self.bounded()

    def test_sigkill_of_whole_group_recovers_manifest(self):
        child, evidence = self.launch("hold")
        generator = self.ready(evidence)
        self.killed(child)
        os.killpg(generator, signal.SIGKILL)
        successor, _ = self.launch()
        self.assertIn("Recovered abandoned", self.completed(successor))
        self.bounded()

    def test_term_waiting_for_another_invocation_leaves_its_extract(self):
        first, evidence = self.launch("hold")
        self.ready(evidence)
        second, second_evidence = self.launch()
        self.wait_file(second_evidence / "wrapper-ready")
        second.terminate()
        self.completed(second, 143)
        self.assertFalse((second_evidence / "ready").exists())
        self.assertTrue((self.cache / (self.digest + ".tmp")).exists())
        first.terminate()
        self.completed(first, 143)
        self.bounded()

    def test_invalid_manifest_retains_cache_and_fails_closed(self):
        state = self.cache / STATE
        state.mkdir()
        (state / "run.json").write_text('{"version": 1, "owned": ["../outside"]}')
        child, evidence = self.launch()
        self.assertIn("retaining ownership", self.completed(child, 1))
        self.assertFalse((evidence / "ready").exists())
        self.assertTrue((self.sentinel / "keep").exists())
        self.assertTrue((state / "run.json").exists())

    def test_multiple_archives_are_refused_before_generator(self):
        (self.stage / "other.zip").write_bytes(b"other archive")
        child, evidence = self.launch()
        self.assertIn("exactly one", self.completed(child, 1))
        self.assertFalse((evidence / "ready").exists())
        self.bounded()


if __name__ == "__main__":
    if sys.argv[1:2] == ["--launch"]:
        module = load_wrapper(sys.argv[2])
        def fake_cache():
            (Path(os.environ["EVIDENCE"]) / "wrapper-ready").touch()
            return Path(sys.argv[3])
        module.native_cache = fake_cache
        sys.exit(module.main(sys.argv[4:]))
    unittest.main()

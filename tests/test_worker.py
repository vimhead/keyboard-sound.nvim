import hashlib
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKER = ROOT / "worker" / "target" / "release" / "keyboard-sound-worker"
if not WORKER.exists():
    WORKER = WORKER.with_suffix(".exe")


class WorkerTests(unittest.TestCase):
    def run_worker(self, requests):
        return subprocess.run(
            [str(WORKER)],
            input="".join(json.dumps(request) + "\n" for request in requests),
            text=True,
            capture_output=True,
            timeout=5,
            check=False,
        )

    def test_decodes_samples_without_device(self):
        result = subprocess.run(
            [str(WORKER), "--check"],
            text=True,
            capture_output=True,
            timeout=5,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "Decoded 8 keyboard samples.")

    def test_eof_exits_without_opening_device(self):
        result = self.run_worker([])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")

    def test_muted_protocol_never_needs_device(self):
        result = self.run_worker([
            {"type": "configure", "is_enabled": False, "volume": 50},
            {"type": "click", "sound": 7, "queued_at_millis": 0},
            {"type": "configure", "is_enabled": True, "volume": 0},
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")

    def test_invalid_protocol_exits_with_error(self):
        result = self.run_worker([
            {"type": "configure", "is_enabled": True, "volume": 101}
        ])
        self.assertEqual(result.returncode, 1)
        self.assertIn("volume exceeds 100", result.stderr)

    def test_sample_provenance_checksums(self):
        provenance = json.loads((ROOT / "assets/sounds/provenance.json").read_text())
        for clip in provenance["clips"]:
            with self.subTest(sample=clip["file"]):
                sample = ROOT / "assets/sounds" / clip["file"]
                self.assertEqual(hashlib.sha256(sample.read_bytes()).hexdigest(), clip["sha256"])


if __name__ == "__main__":
    unittest.main()

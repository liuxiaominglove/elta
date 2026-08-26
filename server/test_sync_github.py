import os
import sys
import json
import unittest
import tempfile
import importlib.util

_SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _SERVER_DIR)

_spec = importlib.util.spec_from_file_location(
    "sync_github", os.path.join(_SERVER_DIR, "sync-github.py"))
sync_github = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sync_github)


class SyncGitHubTests(unittest.TestCase):
    def test_fetch_failure_preserves_existing_github_json(self):
        with tempfile.TemporaryDirectory() as d:
            gj = os.path.join(d, "github.json")
            with open(gj, "w", encoding="utf-8") as f:
                json.dump({"total": 123, "version": "v5.5.1", "byVersion": {"5.5.1": 123}}, f)
            orig = (sync_github.DATA_DIR, sync_github.GITHUB_JSON, sync_github.fetch_github_total)
            try:
                sync_github.DATA_DIR = d
                sync_github.GITHUB_JSON = gj

                def boom():
                    raise RuntimeError("network down")

                sync_github.fetch_github_total = boom
                with self.assertRaises(SystemExit):
                    sync_github.main()
                with open(gj, encoding="utf-8") as f:
                    data = json.load(f)
                self.assertEqual(data["total"], 123)
            finally:
                sync_github.DATA_DIR, sync_github.GITHUB_JSON, sync_github.fetch_github_total = orig

    def test_fetch_success_writes_github_json(self):
        with tempfile.TemporaryDirectory() as d:
            gj = os.path.join(d, "github.json")
            orig = (sync_github.DATA_DIR, sync_github.GITHUB_JSON, sync_github.fetch_github_total)
            try:
                sync_github.DATA_DIR = d
                sync_github.GITHUB_JSON = gj
                sync_github.fetch_github_total = lambda: {"total": 45, "version": "v5.5.1", "byVersion": {"5.5.1": 45}}
                sync_github.main()
                with open(gj, encoding="utf-8") as f:
                    data = json.load(f)
                self.assertEqual(data["total"], 45)
            finally:
                sync_github.DATA_DIR, sync_github.GITHUB_JSON, sync_github.fetch_github_total = orig


if __name__ == "__main__":
    unittest.main()

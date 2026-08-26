import os
import sys
import json
import unittest
import tempfile
import importlib.util

_SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _SERVER_DIR)

import core
import downloads as dl

_spec = importlib.util.spec_from_file_location(
    "count_downloads", os.path.join(_SERVER_DIR, "count-downloads.py"))
count_downloads = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(count_downloads)


def nginx_line(path="/download/ELTA.v5.5.0.dmg"):
    return ('59.83.208.107 - - [24/Aug/2026:00:03:39 +0800] '
            f'"GET {path} HTTP/1.1" 200 1 "-" "Mozilla/5.0" "-"')


class CountDownloadsTests(unittest.TestCase):
    def test_build_downloads_merges_github_by_version(self):
        lines = [nginx_line()]
        out = count_downloads.build_downloads(
            lines, github_total=5, github_by_version={"5.5.1": 5})
        self.assertEqual(out["total"], 6)  # nginx 1 + github 5
        self.assertEqual(out["byVersion"], {"5.5.0": 1, "5.5.1": 5})

    def test_load_github_non_dict_json(self):
        with tempfile.TemporaryDirectory() as d:
            gj = os.path.join(d, "github.json")
            with open(gj, "w", encoding="utf-8") as f:
                f.write("null")
            total, bv = count_downloads.load_github(gj)
            self.assertEqual((total, bv), (0, {}))

    def test_load_github_missing_file(self):
        with tempfile.TemporaryDirectory() as d:
            total, bv = count_downloads.load_github(os.path.join(d, "nope.json"))
            self.assertEqual((total, bv), (0, {}))


if __name__ == "__main__":
    unittest.main()

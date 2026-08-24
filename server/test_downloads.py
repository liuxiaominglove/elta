import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import downloads as dl


def line(method="GET", path="/download/ELTA.v5.5.0.dmg", status=200,
         date="24/Aug/2026:00:03:39 +0800"):
    return (f'59.83.208.107 - - [{date}] "{method} {path} HTTP/1.1" '
            f'{status} 1390987 "-" "Mozilla/5.0" "-"')


class DownloadsTests(unittest.TestCase):
    def test_versioned_url_200_counted(self):
        self.assertEqual(dl.parse_nginx_line(line()), "5.5.0")

    def test_latest_206_counted(self):
        l = line(path="/download/latest.dmg", status=206)
        self.assertEqual(dl.parse_nginx_line(l), "latest")

    def test_head_ignored(self):
        self.assertIsNone(dl.parse_nginx_line(line(method="HEAD")))

    def test_404_ignored(self):
        self.assertIsNone(dl.parse_nginx_line(line(status=404)))

    def test_non_download_path_ignored(self):
        self.assertIsNone(dl.parse_nginx_line(line(path="/style.css")))

    def test_extract_version(self):
        self.assertEqual(dl.extract_version("ELTA.v5.5.0.dmg"), "5.5.0")
        self.assertEqual(dl.extract_version("latest.dmg"), "latest")

    def test_aggregate(self):
        lines = [
            line(),
            line(path="/download/latest.dmg", status=206),
            line(path="/style.css"),
            line(method="HEAD"),
        ]
        agg = dl.aggregate_nginx(lines)
        self.assertEqual(agg["total"], 2)
        self.assertEqual(agg["byVersion"], {"5.5.0": 1, "latest": 1})

    def test_github_extract(self):
        data = {
            "tag_name": "v5.5.0",
            "assets": [
                {"name": "ELTA.v5.5.0.dmg", "download_count": 42},
                {"name": "src.zip", "download_count": 9},
            ],
        }
        self.assertEqual(dl.parse_github_release(data)["total"], 42)

    def test_github_no_asset(self):
        self.assertEqual(dl.parse_github_release({"tag_name": "v5.5.0", "assets": []})["total"], 0)

    def test_merge(self):
        nginx = {"total": 10, "byVersion": {"5.5.0": 10}}
        github = {"total": 5}
        merged = dl.merge(nginx, github)
        self.assertEqual(merged["total"], 15)
        self.assertEqual(merged["byVersion"], {"5.5.0": 10})

    def test_parse_date(self):
        self.assertEqual(dl.parse_nginx_date(line()), "2026-08-24")

    def test_parse_date_malformed(self):
        self.assertIsNone(dl.parse_nginx_date("garbage line without date"))


if __name__ == "__main__":
    unittest.main()

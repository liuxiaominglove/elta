import os
import sys
import unittest
import tempfile
import shutil
import json
import threading
import base64
import urllib.request
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import server as srv


class ServerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.admin_html = os.path.join(self.tmp, "admin.html")
        with open(self.admin_html, "w", encoding="utf-8") as f:
            f.write("<html>admin dashboard</html>")
        self.app = srv.App(data_dir=self.tmp, admin_password="secret",
                           admin_html_path=self.admin_html)
        self._write_latest("5.6.0", "https://autoelta.com/download/ELTA.v5.6.0.dmg")
        self.httpd = srv.make_server(self.app, 0)
        self.port = self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _write_latest(self, version, url):
        with open(os.path.join(self.tmp, "latest.json"), "w", encoding="utf-8") as f:
            json.dump({"version": version, "url": url}, f)

    def _url(self, path):
        return f"http://127.0.0.1:{self.port}{path}"

    def _basic(self, password):
        token = base64.b64encode(f"admin:{password}".encode()).decode()
        return {"Authorization": f"Basic {token}"}

    def get(self, path, headers=None):
        req = urllib.request.Request(self._url(path), headers=headers or {})
        try:
            with urllib.request.urlopen(req) as r:
                body = r.read().decode("utf-8")
                try:
                    return r.status, json.loads(body)
                except json.JSONDecodeError:
                    return r.status, body
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8")
            try:
                return e.code, json.loads(body)
            except json.JSONDecodeError:
                return e.code, body

    def _active_users(self):
        code, data = self.get("/api/stats", headers=self._basic("secret"))
        return data.get("activeUsersToday")

    def test_update_returns_version_and_records(self):
        code, data = self.get("/api/update?id=a")
        self.assertEqual(code, 200)
        self.assertEqual(data["version"], "5.6.0")
        self.assertEqual(data["url"], "https://autoelta.com/download/ELTA.v5.6.0.dmg")
        self.assertEqual(self._active_users(), 1)

    def test_update_same_id_same_day_not_double_count(self):
        self.get("/api/update?id=a")
        self.get("/api/update?id=a")
        self.assertEqual(self._active_users(), 1)

    def test_update_no_id_falls_back_to_ip(self):
        self.get("/api/update")
        self.get("/api/update")
        self.assertEqual(self._active_users(), 1)

    def test_update_no_id_respects_x_real_ip(self):
        self.get("/api/update", headers={"X-Real-IP": "1.2.3.4"})
        self.get("/api/update", headers={"X-Real-IP": "5.6.7.8"})
        self.assertEqual(self._active_users(), 2)

    def test_update_no_id_same_x_real_ip_deduped(self):
        self.get("/api/update", headers={"X-Real-IP": "1.2.3.4"})
        self.get("/api/update", headers={"X-Real-IP": "1.2.3.4"})
        self.assertEqual(self._active_users(), 1)

    def test_update_missing_latest_returns_null_version(self):
        os.remove(os.path.join(self.tmp, "latest.json"))
        code, data = self.get("/api/update?id=a")
        self.assertEqual(code, 200)
        self.assertIsNone(data["version"])

    def test_stats_requires_auth(self):
        code, _ = self.get("/api/stats")
        self.assertEqual(code, 401)

    def test_stats_wrong_password(self):
        code, _ = self.get("/api/stats", headers=self._basic("wrong"))
        self.assertEqual(code, 401)

    def test_stats_correct_password(self):
        code, data = self.get("/api/stats", headers=self._basic("secret"))
        self.assertEqual(code, 200)
        self.assertIn("activeUsersToday", data)

    def test_admin_requires_auth(self):
        code, _ = self.get("/admin")
        self.assertEqual(code, 401)

    def test_admin_401_includes_www_authenticate(self):
        req = urllib.request.Request(self._url("/admin"))
        try:
            urllib.request.urlopen(req)
            self.fail("should 401")
        except urllib.error.HTTPError as e:
            self.assertEqual(e.code, 401)
            self.assertIn("Basic", e.headers.get("WWW-Authenticate", ""))

    def test_stats_401_includes_www_authenticate(self):
        req = urllib.request.Request(self._url("/api/stats"))
        try:
            urllib.request.urlopen(req)
            self.fail("should 401")
        except urllib.error.HTTPError as e:
            self.assertEqual(e.code, 401)
            self.assertIn("Basic", e.headers.get("WWW-Authenticate", ""))

    def test_admin_serves_html_when_authed(self):
        code, body = self.get("/admin", headers=self._basic("secret"))
        self.assertEqual(code, 200)
        self.assertIn("admin dashboard", body)

    def test_unknown_path_404(self):
        code, _ = self.get("/nope")
        self.assertEqual(code, 404)


if __name__ == "__main__":
    unittest.main()

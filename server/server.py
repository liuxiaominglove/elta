"""ELTA 使用统计 + 更新检查服务（单文件，Python 标准库，零依赖）。

端点：
    GET /api/update?id=<匿名UUID>   -> 返回 {version, url}，并记录当日使用（去重）
    GET /api/stats                  -> 汇总（需 Basic Auth）
    GET /admin                      -> 私有看板页（需 Basic Auth）

存储：
    usage.json     当日不同使用者（匿名 id 去重，ip 兜底不落库）
    latest.json    最新版本（由服务器 sync-elta-release.sh 写入）
    downloads.json 下载量聚合（由 count-downloads.py / sync-github.py 写入）
"""

import base64
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

import core

AUTH_USER = "admin"


class App:
    def __init__(self, data_dir, admin_password, admin_html_path=None):
        self.data_dir = data_dir
        self.admin_password = admin_password
        self.admin_html_path = admin_html_path or os.path.join(
            os.path.dirname(os.path.abspath(__file__)), "admin.html")
        self.store = core.UsageStore(os.path.join(data_dir, "usage.json"))
        self.latest_json = os.path.join(data_dir, "latest.json")
        self.downloads_json = os.path.join(data_dir, "downloads.json")

    def read_latest(self):
        try:
            with open(self.latest_json, "r", encoding="utf-8") as f:
                data = json.load(f)
            return {
                "version": data.get("version"),
                "url": data.get("url"),
            }
        except (OSError, json.JSONDecodeError, ValueError):
            return {"version": None, "url": None}

    def read_downloads(self):
        try:
            with open(self.downloads_json, "r", encoding="utf-8") as f:
                data = json.load(f)
            return {
                "total": data.get("total", 0),
                "today": data.get("today", 0),
                "byVersion": data.get("byVersion", {}),
            }
        except (OSError, json.JSONDecodeError, ValueError):
            return {"total": 0, "today": 0, "byVersion": {}}


def _send_json(handler, status, payload):
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(body)


def _send_html(handler, status, html):
    body = html.encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "text/html; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(body)


def _check_auth(handler, password):
    if not password:
        return False
    header = handler.headers.get("Authorization", "")
    if not header.startswith("Basic "):
        return False
    try:
        decoded = base64.b64decode(header[len("Basic "):]).decode("utf-8")
    except Exception:
        return False
    return decoded == f"{AUTH_USER}:{password}"


class Handler(BaseHTTPRequestHandler):
    @property
    def app(self):
        return self.server.app

    def log_message(self, *args):
        pass

    def _client_ip(self):
        x_real = self.headers.get("X-Real-IP")
        if x_real:
            return x_real.strip()
        xff = self.headers.get("X-Forwarded-For")
        if xff:
            return xff.split(",")[0].strip()
        return self.client_address[0]

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        query = parse_qs(parsed.query)

        if path == "/api/update":
            uid = query.get("id", [None])[0]
            self.app.store.record(uid, core.today_key(), self._client_ip())
            _send_json(self, 200, self.app.read_latest())
            return

        if path == "/api/stats":
            if not _check_auth(self, self.app.admin_password):
                _send_json(self, 401, {"error": "unauthorized"})
                return
            downloads = self.app.read_downloads()
            _send_json(self, 200, {
                "activeUsersToday": self.app.store.active_users_on(core.today_key()),
                "downloadsTotal": downloads["total"],
                "downloadsToday": downloads["today"],
                "downloadsByVersion": downloads["byVersion"],
            })
            return

        if path == "/admin":
            if not _check_auth(self, self.app.admin_password):
                _send_html(self, 401, "<h1>401 Unauthorized</h1>")
                return
            try:
                with open(self.app.admin_html_path, "r", encoding="utf-8") as f:
                    html = f.read()
                _send_html(self, 200, html)
            except OSError:
                _send_html(self, 404, "<h1>404 Not Found</h1>")
            return

        _send_json(self, 404, {"error": "not found"})


def make_server(app, port):
    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    httpd.app = app
    return httpd


def main():
    data_dir = os.environ.get("ELTA_DATA_DIR", "/var/www/elta-api")
    password = os.environ.get("ELTA_ADMIN_PASSWORD", "")
    port = int(os.environ.get("ELTA_PORT", "8787"))
    app = App(data_dir=data_dir, admin_password=password)
    httpd = make_server(app, port)
    print(f"elta-api listening on 127.0.0.1:{port}")
    httpd.serve_forever()


if __name__ == "__main__":
    main()

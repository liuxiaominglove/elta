#!/usr/bin/env python3
"""cron 入口：拉取 GitHub 最新 release 下载数，写入 github.json。

环境变量：
    ELTA_DATA_DIR  数据目录（默认 /var/www/elta-api）
"""

import json
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import downloads as dl

REPO = "liuxiaominglove/elta"
DATA_DIR = os.environ.get("ELTA_DATA_DIR", "/var/www/elta-api")
GITHUB_JSON = os.path.join(DATA_DIR, "github.json")


def fetch_github_total():
    url = f"https://api.github.com/repos/{REPO}/releases/latest"
    req = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "ELTA-stats",
    })
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.loads(r.read().decode("utf-8"))
    return dl.parse_github_release(data)


def main():
    try:
        result = fetch_github_total()
    except Exception:
        result = {"total": 0, "version": None}
    os.makedirs(DATA_DIR, exist_ok=True)
    tmp = GITHUB_JSON + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    os.replace(tmp, GITHUB_JSON)
    print(f"github downloads: total={result['total']} version={result['version']}")


if __name__ == "__main__":
    main()

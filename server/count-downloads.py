#!/usr/bin/env python3
"""cron 入口：解析 nginx 日志写 downloads.json（total/today/byVersion），并合并 GitHub 下载数。

环境变量：
    ELTA_NGINX_LOG   nginx 访问日志路径（默认 /var/log/nginx/elta-access.log）
    ELTA_DATA_DIR    数据目录（默认 /var/www/elta-api）
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import core
import downloads as dl

LOG = os.environ.get("ELTA_NGINX_LOG", "/var/log/nginx/elta-access.log")
DATA_DIR = os.environ.get("ELTA_DATA_DIR", "/var/www/elta-api")
GITHUB_JSON = os.path.join(DATA_DIR, "github.json")
DOWNLOADS_JSON = os.path.join(DATA_DIR, "downloads.json")


def build_downloads(lines, github_total):
    today = core.today_key()
    today_lines = [l for l in lines if dl.parse_nginx_date(l) == today]
    all_agg = dl.aggregate_nginx(lines)
    today_agg = dl.aggregate_nginx(today_lines)
    return {
        "total": all_agg["total"] + github_total,
        "today": today_agg["total"],
        "byVersion": all_agg["byVersion"],
    }


def main():
    lines = dl.read_log_lines(LOG)

    github_total = 0
    try:
        with open(GITHUB_JSON, "r", encoding="utf-8") as f:
            github_total = json.load(f).get("total", 0)
    except (OSError, json.JSONDecodeError, ValueError):
        github_total = 0

    out = build_downloads(lines, github_total)
    os.makedirs(DATA_DIR, exist_ok=True)
    tmp = DOWNLOADS_JSON + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    os.replace(tmp, DOWNLOADS_JSON)
    print(f"downloads: total={out['total']} today={out['today']} byVersion={out['byVersion']}")


if __name__ == "__main__":
    main()

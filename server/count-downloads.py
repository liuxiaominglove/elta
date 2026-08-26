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


def load_github(path):
    """读取 github.json 的 total 与 byVersion；文件缺失/损坏/非对象 JSON 时返回 (0, {})。"""
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError, ValueError):
        return 0, {}
    if not isinstance(data, dict):
        return 0, {}
    return data.get("total", 0) or 0, data.get("byVersion", {}) or {}


def build_downloads(lines, github_total, github_by_version=None):
    today = core.today_key()
    today_lines = [l for l in lines if dl.parse_nginx_date(l) == today]
    all_agg = dl.aggregate_nginx(lines)
    today_agg = dl.aggregate_nginx(today_lines)
    by_version = dict(all_agg["byVersion"])
    for k, v in (github_by_version or {}).items():
        by_version[k] = by_version.get(k, 0) + v
    return {
        "total": all_agg["total"] + github_total,
        "today": today_agg["total"],
        "byVersion": by_version,
    }


def main():
    lines = dl.read_log_lines(LOG)

    github_total, github_by_version = load_github(GITHUB_JSON)

    out = build_downloads(lines, github_total, github_by_version)
    os.makedirs(DATA_DIR, exist_ok=True)
    tmp = DOWNLOADS_JSON + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    os.replace(tmp, DOWNLOADS_JSON)
    print(f"downloads: total={out['total']} today={out['today']} byVersion={out['byVersion']}")


if __name__ == "__main__":
    main()

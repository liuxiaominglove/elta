"""ELTA 下载量聚合：nginx 日志解析 + GitHub release 下载数。

nginx 日志为 combined 格式：
    $remote_addr - $remote_user [$time_local] "$request" $status $bytes ...

只统计：GET + 状态 200/206 + 路径以 /download/ 开头且以 .dmg 结尾 的请求。
"""

import datetime
import glob
import gzip
import re

LOG_RE = re.compile(r'^\S+ \S+ \S+ \[[^\]]*\] "([^"]*)" (\d{3}) ')
DATE_RE = re.compile(r'\[(\d{1,2})/([A-Za-z]{3})/(\d{4}):')
VERSIONED_RE = re.compile(r'^ELTA\.v(.+)\.dmg$')


def extract_version(filename):
    """把 DMG 文件名映射为版本标签。latest.dmg 视为 'latest'。"""
    if filename == "latest.dmg":
        return "latest"
    m = VERSIONED_RE.match(filename)
    if m:
        return m.group(1)
    return filename


def parse_nginx_line(line):
    """可计数的下载请求返回版本标签，否则返回 None。"""
    m = LOG_RE.match(line)
    if not m:
        return None
    request = m.group(1)
    status = int(m.group(2))
    parts = request.split()
    if len(parts) < 2:
        return None
    method, path = parts[0], parts[1]
    if method != "GET":
        return None
    if status not in (200, 206):
        return None
    # 剥离 query string（如 ?ref=homepage / 缓存参数），避免 .dmg 结尾判断与版本提取被破坏
    path = path.split("?", 1)[0]
    if not path.startswith("/download/"):
        return None
    if not path.endswith(".dmg"):
        return None
    return extract_version(path[len("/download/"):])


def parse_nginx_date(line):
    m = DATE_RE.search(line)
    if not m:
        return None
    try:
        d = datetime.datetime.strptime(
            f"{m.group(1)}/{m.group(2)}/{m.group(3)}", "%d/%b/%Y")
    except ValueError:
        return None
    return d.strftime("%Y-%m-%d")


def aggregate_nginx(lines):
    by_version = {}
    total = 0
    for ln in lines:
        label = parse_nginx_line(ln)
        if label is None:
            continue
        by_version[label] = by_version.get(label, 0) + 1
        total += 1
    return {"total": total, "byVersion": by_version}


def parse_github_releases(releases):
    """汇总所有 release 的 .dmg 资产下载数，并按版本归集（下载数是 per-asset 的）。"""
    total = 0
    version = None
    by_version = {}
    for rel in releases:
        if version is None:
            version = rel.get("tag_name")
        for a in rel.get("assets", []):
            name = str(a.get("name", ""))
            if name.endswith(".dmg"):
                count = int(a.get("download_count", 0))
                total += count
                label = extract_version(name)
                by_version[label] = by_version.get(label, 0) + count
    return {"total": total, "version": version, "byVersion": by_version}


def merge(nginx, github):
    by_version = dict(nginx["byVersion"])
    for k, v in (github.get("byVersion") or {}).items():
        by_version[k] = by_version.get(k, 0) + v
    return {
        "total": nginx["total"] + github["total"],
        "byVersion": by_version,
    }


def read_log_lines(log_path):
    """读取当前 + 轮转日志（含 .gz）的所有行，按文件名排序。"""
    lines = []
    paths = sorted(set([log_path] + glob.glob(log_path + "*")))
    for p in paths:
        try:
            if p.endswith(".gz"):
                with gzip.open(p, "rt", encoding="utf-8", errors="replace") as f:
                    lines.extend(f.readlines())
            else:
                with open(p, "r", encoding="utf-8", errors="replace") as f:
                    lines.extend(f.readlines())
        except OSError:
            continue
    return lines

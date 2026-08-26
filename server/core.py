"""ELTA 使用统计核心：匿名安装 ID 去重存储 + IP 兜底（不落库）。

存储格式（JSON 文件）：
    {"2026-08-24": ["uuid1", "uuid2", ...], ...}

去重规则：
    - 有 id  -> 按 (date, id) 去重，id 持久化。
    - 无 id  -> 按 (date, ip) 去重，ip 仅在进程内存中保留，绝不写盘。
"""

import json
import os
import threading
import datetime


def today_key():
    """本机时区的当日键（YYYY-MM-DD），与服务器本地时区一致。"""
    return datetime.date.today().isoformat()


def _normalize_id(value):
    if value is None:
        return None
    s = str(value).strip()
    return s or None


def _normalize_ip(value):
    if value is None:
        return None
    s = str(value).strip()
    return s or None


class UsageStore:
    def __init__(self, path):
        self.path = path
        self._lock = threading.Lock()
        self._ids = {}       # {date: {id: True}}
        self._ip_seen = {}   # {date: {ip: True}}  内存态，不持久化
        self._load()

    def _load(self):
        if not self.path or not os.path.exists(self.path):
            return
        try:
            with open(self.path, "r", encoding="utf-8") as f:
                raw = json.load(f)
            if not isinstance(raw, dict):
                return
            self._ids = {
                date: {str(i): True for i in ids}
                for date, ids in raw.items()
                if isinstance(ids, list)
            }
        except (json.JSONDecodeError, OSError, ValueError):
            self._ids = {}

    def _persist(self):
        if not self.path:
            return
        serializable = {
            date: sorted(ids.keys())
            for date, ids in self._ids.items()
        }
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(serializable, f, ensure_ascii=False, indent=2)
        os.replace(tmp, self.path)

    def record(self, uid, date, ip=None):
        """记录一次使用。返回 True 表示该 (date, 键) 首次计入。"""
        uid = _normalize_id(uid)
        ip = _normalize_ip(ip)
        date = (date or today_key())
        with self._lock:
            if uid:
                bucket = self._ids.setdefault(date, {})
                if uid in bucket:
                    return False
                bucket[uid] = True
                try:
                    self._persist()
                except Exception:
                    # 持久化失败回滚内存，避免「假去重」让该 uid 永远不再落盘
                    del bucket[uid]
                    if not bucket:
                        self._ids.pop(date, None)
                    raise
                return True
            if ip:
                bucket = self._ip_seen.setdefault(date, {})
                if ip in bucket:
                    return False
                bucket[ip] = True
                # 剪除过期日期桶：仅今日会被查询，防止内存随天数/IP 数线性增长
                for d in [k for k in self._ip_seen if k < date]:
                    del self._ip_seen[d]
                return True
            return False

    def active_users_on(self, date):
        """某日不同使用人数 = 持久化的 id 数 + 内存态 ip 兜底数。"""
        date = date or today_key()
        with self._lock:
            n = len(self._ids.get(date, {}))
            n += len(self._ip_seen.get(date, {}))
            return n

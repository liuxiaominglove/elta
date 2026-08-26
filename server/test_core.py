import os
import sys
import unittest
import tempfile
import shutil

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import core


class UsageStoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.path = os.path.join(self.tmp, "usage.json")
        self.store = core.UsageStore(self.path)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_same_id_same_day_deduped(self):
        self.assertTrue(self.store.record("a", "2026-08-24"))
        self.assertFalse(self.store.record("a", "2026-08-24"))
        self.assertEqual(self.store.active_users_on("2026-08-24"), 1)

    def test_different_ids_same_day(self):
        self.assertTrue(self.store.record("a", "2026-08-24"))
        self.assertTrue(self.store.record("b", "2026-08-24"))
        self.assertEqual(self.store.active_users_on("2026-08-24"), 2)

    def test_ip_fallback_dedupes_when_no_id(self):
        self.assertTrue(self.store.record(None, "2026-08-24", ip="1.1.1.1"))
        self.assertFalse(self.store.record(None, "2026-08-24", ip="1.1.1.1"))
        self.assertEqual(self.store.active_users_on("2026-08-24"), 1)

    def test_id_takes_precedence_over_ip(self):
        self.assertTrue(self.store.record("a", "2026-08-24", ip="1.1.1.1"))
        self.assertTrue(self.store.record("b", "2026-08-24", ip="1.1.1.1"))
        self.assertEqual(self.store.active_users_on("2026-08-24"), 2)

    def test_ip_not_persisted(self):
        self.store.record("some-id", "2026-08-24")
        self.store.record(None, "2026-08-24", ip="203.0.113.7")
        with open(self.path) as f:
            raw = f.read()
        self.assertIn("some-id", raw)
        self.assertNotIn("203.0.113.7", raw)
        self.assertNotIn("ip", raw)

    def test_ip_only_record_never_touches_disk(self):
        self.store.record(None, "2026-08-24", ip="203.0.113.7")
        self.assertFalse(os.path.exists(self.path))

    def test_empty_id_and_ip_ignored(self):
        self.assertFalse(self.store.record("", "2026-08-24", ip=None))
        self.assertFalse(self.store.record(None, "2026-08-24", ip=""))
        self.assertEqual(self.store.active_users_on("2026-08-24"), 0)

    def test_corrupted_store_falls_back_to_empty(self):
        with open(self.path, "w") as f:
            f.write("{ not valid json !!!")
        store = core.UsageStore(self.path)
        self.assertEqual(store.active_users_on("2026-08-24"), 0)
        self.assertTrue(store.record("a", "2026-08-24"))

    def test_persistence_survives_reload(self):
        self.store.record("a", "2026-08-24")
        self.store.record("b", "2026-08-24")
        reloaded = core.UsageStore(self.path)
        self.assertEqual(reloaded.active_users_on("2026-08-24"), 2)

    def test_cross_day_isolation(self):
        self.assertTrue(self.store.record("a", "2026-08-24"))
        self.assertTrue(self.store.record("a", "2026-08-25"))
        self.assertEqual(self.store.active_users_on("2026-08-24"), 1)
        self.assertEqual(self.store.active_users_on("2026-08-25"), 1)

    def test_today_key_format(self):
        key = core.today_key()
        self.assertRegex(key, r"^\d{4}-\d{2}-\d{2}$")

    def test_record_persist_failure_does_not_corrupt_memory(self):
        self.assertTrue(self.store.record("a", "2026-08-24"))
        original = self.store._persist

        def boom():
            raise OSError("disk full")

        self.store._persist = boom
        try:
            with self.assertRaises(OSError):
                self.store.record("b", "2026-08-24")
        finally:
            self.store._persist = original

        # b 未持久化成功，内存应回滚，不能留下「假去重」导致永远不再落盘
        self.assertEqual(self.store.active_users_on("2026-08-24"), 1)
        # 恢复后重试应成功
        self.assertTrue(self.store.record("b", "2026-08-24"))
        self.assertEqual(self.store.active_users_on("2026-08-24"), 2)

    def test_ip_seen_pruned_across_days(self):
        self.store.record(None, "2026-08-24", ip="1.1.1.1")
        self.store.record(None, "2026-08-25", ip="2.2.2.2")
        self.store.record(None, "2026-08-26", ip="3.3.3.3")
        # 旧日期桶应被剪除，只保留最近日期，防止内存线性增长
        self.assertNotIn("2026-08-24", self.store._ip_seen)
        self.assertNotIn("2026-08-25", self.store._ip_seen)
        self.assertIn("2026-08-26", self.store._ip_seen)


if __name__ == "__main__":
    unittest.main()

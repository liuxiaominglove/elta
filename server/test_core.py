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


if __name__ == "__main__":
    unittest.main()

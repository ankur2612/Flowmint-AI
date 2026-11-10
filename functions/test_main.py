"""Deterministic tests for payment logic that does not need PayPal or Firestore.

Run: venv\\Scripts\\python -m unittest test_main
"""

import unittest
from datetime import datetime
from unittest import mock

import firebase_admin

with mock.patch.object(firebase_admin, "initialize_app"):
    import main


class IdempotencyFingerprintTest(unittest.TestCase):
    def test_same_cart_in_any_order_matches(self):
        a = main._request_fingerprint("shopping", {"items": [
            {"productId": "p1", "quantity": 1}, {"productId": "p2", "quantity": 2}]})
        b = main._request_fingerprint("shopping", {"items": [
            {"productId": "p2", "quantity": 2}, {"productId": "p1", "quantity": 1}]})
        self.assertEqual(a, b)

    def test_changed_quantity_does_not_match(self):
        a = main._request_fingerprint("shopping", {"items": [{"productId": "p1", "quantity": 1}]})
        b = main._request_fingerprint("shopping", {"items": [{"productId": "p1", "quantity": 3}]})
        self.assertNotEqual(a, b)

    def test_changed_donation_amount_does_not_match(self):
        a = main._request_fingerprint("donation", {"campaignId": "c", "amountMinor": 50000})
        b = main._request_fingerprint("donation", {"campaignId": "c", "amountMinor": 90000})
        self.assertNotEqual(a, b)


class WebhookTargetTest(unittest.TestCase):
    def test_valid_custom_id(self):
        self.assertEqual(main._parse_custom_id({"custom_id": "uid1|shopping|abcdef12-3456"}),
                         ("uid1", "shopping", "abcdef12-3456"))

    def test_rejects_unknown_kind_and_bad_key(self):
        self.assertIsNone(main._parse_custom_id({"custom_id": "uid1|admin|abcdef12"}))
        self.assertIsNone(main._parse_custom_id({"custom_id": "uid1|shopping|../x"}))
        self.assertIsNone(main._parse_custom_id({"custom_id": "|shopping|abcdef12"}))
        self.assertIsNone(main._parse_custom_id({}))


class MoneyAndDatesTest(unittest.TestCase):
    def test_minor_units_to_paypal_value(self):
        self.assertEqual(main._value(240050), "2400.50")
        self.assertEqual(main._value(5), "0.05")

    def test_month_end_is_clamped(self):
        self.assertEqual(main._add_months(datetime(2026, 1, 31), 1), datetime(2026, 2, 28))


class RateLimitTest(unittest.TestCase):
    """Exercises the limiter against an in-memory stand-in for Firestore."""

    def setUp(self):
        self.store = {}
        store = self.store

        class Snap:
            def __init__(self, data):
                self._data = data
                self.exists = data is not None

            def to_dict(self):
                return dict(self._data or {})

        class Ref:
            def __init__(self, key):
                self.key = key

            def get(self, transaction=None):
                return Snap(store.get(self.key))

        class Tx:
            def set(self, ref, data):
                store[ref.key] = data

        class Db:
            def collection(self, _):
                return self

            def document(self, key):
                return Ref(key)

            def transaction(self):
                return Tx()

        patcher_db = mock.patch.object(main, "_db", return_value=Db())
        patcher_tx = mock.patch.object(main.firestore, "transactional", side_effect=lambda f: f)
        patcher_db.start()
        patcher_tx.start()
        self.addCleanup(patcher_db.stop)
        self.addCleanup(patcher_tx.stop)

    def test_blocks_after_limit_within_a_minute(self):
        now = datetime(2026, 11, 11, 10, 0, 5, tzinfo=main.timezone.utc)
        for _ in range(main.RATE_LIMITS["refund"]):
            main._rate_limit("u1", "refund", now)
        with self.assertRaises(main.https_fn.HttpsError) as err:
            main._rate_limit("u1", "refund", now)
        self.assertEqual(err.exception.code, main.Code.RESOURCE_EXHAUSTED)

    def test_resets_in_next_window_and_is_per_user(self):
        now = datetime(2026, 11, 11, 10, 0, 5, tzinfo=main.timezone.utc)
        for _ in range(main.RATE_LIMITS["refund"]):
            main._rate_limit("u1", "refund", now)
        main._rate_limit("u2", "refund", now)
        later = datetime(2026, 11, 11, 10, 1, 1, tzinfo=main.timezone.utc)
        main._rate_limit("u1", "refund", later)


if __name__ == "__main__":
    unittest.main()

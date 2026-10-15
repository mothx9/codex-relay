import datetime as dt
import unittest

import ios_signing_renew as guard


class SigningRenewalTests(unittest.TestCase):
    def test_exact_app_profile_excludes_test_runner(self):
        self.assertTrue(guard.matching_profile({"Entitlements": {
            "application-identifier": "TEAM.net.codex-relay.iphone"}}))
        self.assertFalse(guard.matching_profile({"Entitlements": {
            "application-identifier": "TEAM.net.codex-relay.iphone.uitests.xctrunner"}}))

    def test_renews_before_expiry_but_not_on_every_check(self):
        now = dt.datetime(2026, 10, 15, tzinfo=dt.timezone.utc)
        self.assertFalse(guard.renewal_due(now, now + dt.timedelta(days=4)))
        self.assertTrue(guard.renewal_due(now, now + dt.timedelta(days=3)))
        self.assertTrue(guard.renewal_due(now, now + dt.timedelta(days=4), force=True))

    def test_profile_expiry_is_utc(self):
        naive = dt.datetime(2026, 10, 22, 10, 0)
        self.assertEqual(guard.expires_at(naive).utcoffset(), dt.timedelta())
        self.assertEqual(guard.expires_at("2026-10-22T12:00:00+02:00"),
                         dt.datetime(2026, 10, 22, 10, tzinfo=dt.timezone.utc))


if __name__ == "__main__":
    unittest.main()

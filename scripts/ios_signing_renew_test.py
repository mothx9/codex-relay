import datetime as dt
import subprocess
import unittest
from unittest.mock import patch

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

    def test_unavailable_phone_alerts_once_daily_and_again_at_expiry(self):
        now = dt.datetime(2026, 10, 20, 10, tzinfo=dt.timezone.utc)
        expiry = now + dt.timedelta(days=2)
        self.assertEqual(guard.alert_stage(now, expiry), "due")
        self.assertTrue(guard.should_alert(now, "due", {}))
        alerted = {"stage": "due", "alerted_at": now.isoformat()}
        self.assertFalse(guard.should_alert(now + dt.timedelta(hours=23), "due", alerted))
        self.assertTrue(guard.should_alert(now + dt.timedelta(days=1), "due", alerted))
        self.assertEqual(guard.alert_stage(expiry, expiry), "expired")
        self.assertTrue(guard.should_alert(expiry, "expired", alerted))

    def test_new_schedule_checks_within_fifteen_minutes(self):
        self.assertEqual(guard.launch_agent_value()["StartInterval"], 900)
        self.assertEqual(guard.launch_agent_value(21600)["StartInterval"], 21600)

    def test_device_discovery_timeout_is_a_retryable_wait(self):
        expiry = dt.datetime.now(dt.timezone.utc) - dt.timedelta(minutes=1)
        config = {"device_udid": "test-device", "installed_profile_expires_at": expiry.isoformat()}
        with patch.object(guard, "device_available", side_effect=subprocess.TimeoutExpired("devicectl", 30)), \
             patch.object(guard, "record") as record, \
             patch.object(guard, "alert_unavailable") as alert:
            guard.refresh(config)
        self.assertEqual(record.call_args.args[:2], (config, "waiting_for_iphone"))
        alert.assert_called_once_with(expiry)


if __name__ == "__main__":
    unittest.main()

import datetime
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from prepare import VARIABLES
from testflight import (Connect, distribute, next_build, release_notes,
                        signing_configuration, validate_profile, wait_for_build)


class BuildSelectionTests(unittest.TestCase):
    def test_first_upload_uses_declared_version(self):
        client = Mock()
        client.all.side_effect = [[], []]
        self.assertEqual(next_build(client, "app", 100), 100)

    def test_pending_upload_prevents_reusing_a_number(self):
        client = Mock()
        client.all.side_effect = [
            [{"attributes": {"version": "104"}}],
            [{"attributes": {"cfBundleVersion": "108"}}],
        ]
        self.assertEqual(next_build(client, "app", 100), 109)

    def test_declared_version_remains_a_floor(self):
        client = Mock()
        client.all.side_effect = [[{"attributes": {"version": "2"}}], []]
        self.assertEqual(next_build(client, "app", 100), 100)

    def test_pagination_is_followed(self):
        client = Connect.__new__(Connect)
        client.request = Mock(side_effect=[
            {"data": [1], "links": {"next": "https://api.appstoreconnect.apple.com/v1/builds?cursor=next"}},
            {"data": [2], "links": {"next": None}},
        ])
        self.assertEqual(client.all("/v1/builds", limit=1), [1, 2])

    def test_foreign_pagination_host_never_receives_credentials(self):
        client = Connect.__new__(Connect)
        with self.assertRaisesRegex(ValueError, "pagination host"):
            client.request("GET", "https://example.com/v1/builds")

    def test_failed_processing_stops_distribution(self):
        client = Mock()
        client.all.return_value = [{"attributes": {"processingState": "INVALID"}}]
        with self.assertRaisesRegex(ValueError, "INVALID"):
            wait_for_build(client, "app", "101", "1.0")


class SigningTests(unittest.TestCase):
    def config(self):
        config = {key: (False if kind is bool else "") for key, kind in VARIABLES.items()}
        config.update(telegram_bundle_id="com.example.reference", telegram_team_id="FIXTURE001",
                      telegram_api_id="123", telegram_api_hash="0" * 32,
                      telegram_aps_environment="production", rg_config='{"enabled":true}')
        return signing_configuration(config, "FIXTURE002", "com.example.beta", "12345")

    def profile(self):
        return {
            "Entitlements": {
                "application-identifier": "FIXTURE002.com.example.beta",
                "com.apple.security.application-groups": ["group.com.example.beta"],
                "aps-environment": "production",
                "com.apple.developer.usernotifications.communication": True,
            },
            "TeamIdentifier": ["FIXTURE002"], "DeveloperCertificates": [b"certificate"],
            "ExpirationDate": datetime.datetime.now() + datetime.timedelta(days=30),
        }

    def test_reference_configuration_is_not_mutated(self):
        config = self.config()
        self.assertEqual(config["rg_config"], '{"enabled":true}')
        self.assertEqual(config["telegram_is_appstore_build"], "true")
        self.assertEqual(config["telegram_bundle_id"], "com.example.beta")

    def test_valid_store_profile_is_accepted(self):
        validate_profile(self.profile(), self.config(), "", b"certificate")

    def test_wrong_team_certificate_group_or_distribution_type_is_rejected(self):
        for field, value in [
            ("TeamIdentifier", ["FIXTURE003"]),
            ("DeveloperCertificates", [b"wrong-certificate"]),
            ("ProvisionedDevices", ["device"]),
            ("ProvisionsAllDevices", True),
            ("ExpirationDate", datetime.datetime(2000, 1, 1)),
        ]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate_profile(self.profile() | {field: value}, self.config(), "", b"certificate")
        for field, value in [
            ("get-task-allow", True),
            ("com.apple.security.application-groups", ["group.com.example.other"]),
            ("aps-environment", "development"),
        ]:
            profile = self.profile()
            profile["Entitlements"][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate_profile(profile, self.config(), "", b"certificate")


class DistributionTests(unittest.TestCase):
    def client(self, state="READY_FOR_BETA_SUBMISSION", attached=False):
        client = Mock()
        groups = [{"id": "group", "attributes": {"name": "External", "isInternalGroup": False}}]
        members = [{"id": "build"}] if attached else []
        client.all.side_effect = [groups, [], members, [{"id": "build"}]]
        client.request.side_effect = lambda method, path, data=None: {
            "data": {"id": "detail", "attributes": {"externalBuildState": state}},
        }
        return client

    @patch("testflight.wait_for_build", return_value={"id": "build"})
    def test_upload_is_followed_by_group_attachment_and_beta_review(self, _wait):
        client = self.client()
        distribute(client, "app", "External", "101", "1.0", "Test notifications")
        paths = [(call.args[0], call.args[1]) for call in client.request.call_args_list]
        self.assertIn(("POST", "/v1/betaGroups/group/relationships/builds"), paths)
        self.assertIn(("POST", "/v1/betaAppReviewSubmissions"), paths)

    @patch("testflight.wait_for_build", return_value={"id": "build"})
    def test_retry_does_not_resubmit_review_or_duplicate_membership(self, _wait):
        client = self.client("WAITING_FOR_BETA_REVIEW", attached=True)
        distribute(client, "app", "External", "101", "1.0", "Test notifications")
        paths = [call.args[1] for call in client.request.call_args_list]
        self.assertNotIn("/v1/betaGroups/group/relationships/builds", paths)
        self.assertNotIn("/v1/betaAppReviewSubmissions", paths)

    def test_internal_group_cannot_satisfy_external_distribution(self):
        client = Mock()
        client.all.return_value = [{"attributes": {"name": "External", "isInternalGroup": True}}]
        with self.assertRaisesRegex(ValueError, "external TestFlight"):
            distribute(client, "app", "External", "101", "1.0", "Notes")

    def test_missing_or_oversized_notes_fail_before_upload(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "notes.txt"
            for value in ["", "x" * 4001]:
                path.write_text(value)
                with self.assertRaises(ValueError):
                    release_notes(path)


if __name__ == "__main__":
    unittest.main()

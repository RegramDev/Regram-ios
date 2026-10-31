import datetime
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID

spec = importlib.util.spec_from_file_location("private_command", Path(__file__).with_name("private-command.py"))
private_command = importlib.util.module_from_spec(spec)
spec.loader.exec_module(private_command)


class RedactedSummaryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        key = ec.generate_private_key(ec.SECP256R1())
        subject = x509.Name([
            x509.NameAttribute(NameOID.COMMON_NAME, "Apple Distribution: Fixture Widgets Ltd (FIXTURE001)"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Fixture Widgets Ltd"),
            x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, "FIXTURE001"),
            x509.NameAttribute(NameOID.COUNTRY_NAME, "GB"),
        ])
        now = datetime.datetime.now(datetime.timezone.utc)
        self.certificate = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject)
                            .public_key(key.public_key()).serial_number(1)
                            .not_valid_before(now).not_valid_after(now + datetime.timedelta(days=1))
                            .sign(key, hashes.SHA256()))
        (self.root / "distribution.cer").write_bytes(self.certificate.public_bytes(serialization.Encoding.DER))
        (self.root / "configuration.json").write_text(json.dumps({
            "telegram_team_id": "FIXTURE001", "telegram_api_hash": "a" * 32, "enabled": True}))

    def tearDown(self):
        self.temporary.cleanup()

    def run_summary(self, text):
        with tempfile.TemporaryFile() as log, patch.object(private_command, "ROOT", self.root), \
                patch.dict("os.environ", {"ASC_ISSUER_ID": "issuer-fixture-0001"}):
            log.write(text.encode())
            return private_command.summary(log)

    def test_private_values_are_removed_from_error_lines(self):
        fingerprint = self.certificate.fingerprint(hashes.SHA1()).hex().upper()
        lines = self.run_summary("\n".join([
            "Compiling module",
            "ERROR: signing with 'Apple Distribution: Fixture Widgets Ltd (FIXTURE001)' failed",
            "error: identity " + fingerprint + " for fixture widgets was denied",
            "error: issuer issuer-fixture-0001 rejected key for someone@example.com",
            "error: api hash " + "a" * 32,
            "error: " + "QUJD" * 30,
            "::error::forged workflow command failed",
            "Target //Telegram:Regram failed to build",
        ]))
        text = "\n".join(lines)
        for private in ("Fixture", "Widgets", "FIXTURE001", fingerprint, "issuer-fixture", "example.com", "a" * 32):
            self.assertNotIn(private.lower(), text.lower())
        self.assertNotIn("QUJDQUJD", text)
        self.assertNotIn("Compiling module", text)
        self.assertIn("ERROR: signing with '***' failed", text)
        self.assertIn("Target //Telegram:Regram failed to build", text)
        self.assertIn(": :error: :forged workflow command failed", text)
        self.assertFalse(any(line.startswith("::") for line in lines))

    def test_missing_redaction_inputs_withhold_everything(self):
        (self.root / "distribution.cer").unlink()
        self.assertIsNone(self.run_summary("error: Fixture Widgets failed"))

    def test_long_output_keeps_first_and_last_errors(self):
        lines = self.run_summary("\n".join(f"error: case {n}" for n in range(100)))
        self.assertEqual(lines[0], "error: case 0")
        self.assertEqual(lines[-1], "error: case 99")
        self.assertIn("...", lines)

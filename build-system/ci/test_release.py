"""Offline checks for the explicit-confirmation boundary and selected IPA identity."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import release


class ReleaseChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.ipa = self.root / 'ipa' / 'Regram-13.0-b40001.ipa'
        self.ipa.parent.mkdir()
        with zipfile.ZipFile(self.ipa, 'w') as archive:
            archive.writestr('Payload/Regram.app/Info.plist', plistlib.dumps({
                'CFBundleShortVersionString': '13.0', 'CFBundleVersion': '40001'}))
        self.digest = hashlib.sha256(self.ipa.read_bytes()).hexdigest()
        self.request = {'repository': 'RegramDev/Regram-ios', 'filename': self.ipa.name,
                        'version': '13.0', 'build': '40001', 'source_commit': 'a' * 40,
                        'sha256': self.digest, 'run_url': 'https://github.com/RegramDev/Regram-ios/actions/runs/123'}
        self.request_path = self.root / 'request.json'
        self.request_path.write_text(json.dumps(self.request))
        self.run = {'status': 'completed', 'conclusion': 'success', 'head_branch': 'master',
                    'path': '.github/workflows/build.yml', 'head_sha': 'a' * 40,
                    'event': 'push', 'head_repository': {'full_name': 'RegramDev/Regram-ios'},
                    'html_url': self.request['run_url']}
        self.artifacts = {'artifacts': [{'id': 7, 'name': self.ipa.name, 'expired': False,
                                       'digest': 'sha256:' + self.digest}]}

    def test_no_confirmation_performs_no_reads_or_github_operations(self):
        with patch.object(release, 'api') as api, patch.object(release, 'command') as command:
            with self.assertRaisesRegex(ValueError, 'confirmation'):
                release.publish(self.root / 'nonexistent.json', self.ipa.parent, False)
            api.assert_not_called()
            command.assert_not_called()

    def test_selection_requires_successful_master_build_and_exact_ipa(self):
        for change in [{'conclusion': 'failure'}, {'head_branch': 'other'}, {'path': '.github/workflows/release.yml'}, {'event': 'pull_request'}, {'head_repository': {'full_name': 'somebody/fork'}}]:
            with patch.object(release, 'api', return_value=self.run | change):
                with self.assertRaises(ValueError):
                    release.prepare('RegramDev/Regram-ios', '123', self.ipa.name, self.request_path)
        with patch.object(release, 'api', side_effect=[self.run, self.artifacts]):
            selected = release.prepare('RegramDev/Regram-ios', '123', self.ipa.name, self.request_path)
            self.assertEqual(selected['artifact_id'], 7)
            self.assertEqual(selected['sha256'], self.digest)
        with patch.object(release, 'api', side_effect=[self.run, {'artifacts': []}]):
            with self.assertRaises(ValueError):
                release.prepare('RegramDev/Regram-ios', '123', self.ipa.name, self.request_path)

    def test_rejects_wrong_filename_digest_and_embedded_build(self):
        for request in [self.request | {'sha256': '0' * 64}, self.request | {'filename': 'Regram-13.0-b40002.ipa'}]:
            with self.assertRaises(ValueError):
                release.verify_ipa(self.ipa, request)
        with zipfile.ZipFile(self.ipa, 'w') as archive:
            archive.writestr('Payload/Regram.app/Info.plist', plistlib.dumps({
                'CFBundleShortVersionString': '13.0', 'CFBundleVersion': '40002'}))
        changed = self.request | {'sha256': hashlib.sha256(self.ipa.read_bytes()).hexdigest()}
        with self.assertRaisesRegex(ValueError, 'version/build'):
            release.verify_ipa(self.ipa, changed)
        for filename in ['../Regram-13.0-b40001.ipa', 'Regram-13.0-b40001-LCSign-reference.ipa']:
            with self.assertRaises(ValueError):
                release.filename_parts(filename)

    @patch.dict(os.environ, {'GITHUB_REPOSITORY': 'RegramDev/Regram-ios'})
    def test_duplicate_tag_and_extra_files_never_create_release(self):
        with patch.object(release, 'api', return_value=[{'ref': 'refs/tags/v13.0-b40001'}]), patch.object(release, 'command') as command:
            with self.assertRaisesRegex(ValueError, 'existing release tag'):
                release.publish(self.request_path, self.ipa.parent, True)
            command.assert_not_called()
        (self.ipa.parent / 'symbols.zip').write_bytes(b'extra')
        with patch.object(release, 'api') as api:
            with self.assertRaisesRegex(ValueError, 'Only the approved IPA'):
                release.publish(self.request_path, self.ipa.parent, True)
            api.assert_not_called()

    @patch.dict(os.environ, {'GITHUB_REPOSITORY': 'RegramDev/Regram-ios'})
    def test_only_publish_after_confirmed_draft_has_the_single_ipa(self):
        with patch.object(release, 'api', return_value=[]), patch.object(release, 'command', side_effect=['', json.dumps({'isDraft': True, 'assets': [{'name': self.ipa.name}]}), '']) as command:
            release.publish(self.request_path, self.ipa.parent, True)
            calls = [call.args[0] for call in command.call_args_list]
            self.assertIn('--draft', calls[0])
            self.assertIn(str(self.ipa), calls[0])
            self.assertIn('--draft=false', calls[-1])
        with patch.object(release, 'api', return_value=[]), patch.object(release, 'command', side_effect=['', json.dumps({'isDraft': True, 'assets': []})]) as command:
            with self.assertRaises(ValueError):
                release.publish(self.request_path, self.ipa.parent, True)
            self.assertEqual(command.call_count, 2)


if __name__ == '__main__':
    unittest.main()
